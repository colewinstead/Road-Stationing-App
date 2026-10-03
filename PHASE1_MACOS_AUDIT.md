# Phase 1 macOS audit and ORD comparison readiness

Audit date: October 3, 2026 (America/Chicago). Phase 1 only. No Phase 2 work,
native UI, GPS, maps, CRS transformations, storage, accounts or cloud features
were added. **Technically ready for human ORD comparison; independently validated
against ORD: NO. Phase 2 remains blocked.**

## 1–5. Environment and local test evidence

| Requested observation | Actual output/result |
| --- | --- |
| macOS | 27.0.1, build 26A434 |
| `xcodebuild -version` | Xcode 27.0; Build version 27A266a |
| `swift --version` | swift-driver 1.168.6; Apple Swift 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1); Target arm64-apple-macosx27.0.0 |
| `xcode-select -p` | /Applications/Xcode.app/Contents/Developer |
| `uname -m` | arm64 (Apple Silicon) |
| Before changes, `swift test` | 122 XCTest tests, 0 failures |
| After changes, `swift test` | 142 XCTest tests, 0 failures; about 1.13 s execution |
| After changes, `swift test -c release` | 142 XCTest tests, 0 failures; about 0.08 s execution |
| New tests | 20: 11 tolerance, 1 ORD tangent, 1 explicit equation branch, 7 validation workflow |

Existing tests/accuracies were retained; none deleted, skipped or relaxed. Swift
Testing's separate "0 tests" footer is unrelated to the 142-test XCTest suite.
Logs for this run: `/tmp/roadstation-baseline.log`, `/tmp/roadstation-debug.log`,
`/tmp/roadstation-release.log`. Build/validation outputs are ignored, not source.

Debug and release CLI analytic examples: **2/2 PASS**, JSON and CSV independently
read back with Python. Wrong expected station returned exit 1 and maximum station
error 1.0; malformed XML returned exit 2; unpopulated ORD template returned exit 1
with 0/32 passed. `git diff --check` passed. No compiler warnings were observed.
These checks are analytic/synthetic evidence, not ORD ground truth.

The existing GitHub Actions workflow is unchanged: Swift 6.0.3 on macOS 14 and
Ubuntu 24.04, debug/release tests and validation CLI. Baseline main commit
`4dbaeb6aade16adc1a851d4adc2e08c79446816c` has a successful
[Actions run](https://github.com/colewinstead/Road-Stationing-App/actions/runs/37091159382).
Changes are submitted as a draft PR for that same matrix; current-revision CI
results belong to the PR checks and are reported separately in the completion
response, rather than inferred from the successful baseline.

## 6–7. Exact tolerance defect and architecture

The parser supplied custom tolerances to arc/spiral construction and Alignment
validation, but Alignment discarded its context afterward. Lines ignored parser
tolerances entirely. Runtime uses of `GeometryTolerances.standard` were present in:

- LineSegment near-zero validation;
- AlignmentEngine bounds pruning, tie/position/tangent ambiguity, on-alignment
  classification and station bounds;
- CircularCurveSegment bounds padding, point bounds, radial-center and endpoint
  tie ambiguity;
- StationingEngine station bounds and inverse-resolution distance deduplication;
- GeometryUtilities.checkedDistance's default argument, used by line/curve and
  alignment/station engines.

Fix: GeometryTolerances is a value type with Equatable conformance. Each immutable
LineSegment, CircularCurveSegment and SpiralSegment stores its validated context.
Alignment stores one coherent context and all of its segments use it. When the
alignment argument is omitted, a common geometry context is inherited; different
contexts require an explicit alignment override. Overrides revalidate lines/arcs
and rebuild spiral integration caches once, during construction. Identical
contexts reuse the geometry. Parsing explicitly supplies the same options to
every geometry and the alignment. No global mutable state was introduced.

Every checkedDistance call now supplies its applicable station tolerance; there
is no fallback default. Queries read the stored context. Remaining `.standard`
references are only initial defaults for parser/geometry creation, plus the
empty-alignment fallback before the existing empty-geometry rejection.

The deliberately non-default tests exercise tight and loose near-zero lines,
parser propagation, each geometry's station bounds, alignment/station bounds,
ON/LT/RT classification, ties that would otherwise be pruned by bounds, tangent
ambiguity, curve-center and arc-endpoint ambiguity, curve padding, inverse
station deduplication, inheritance/mixed-context rejection, explicit override
and invalid contexts. Station gap acceptance remains ULP-based, not engineering
tolerance-based; a test preserves gaps smaller than the configured station
tolerance. Numerical benchmark tolerances were not weakened.

## 3, continued. Tolerance-independent geometry review

Re-reviewed clamped line dot projection; directed radial arc projection and
endpoint comparison; rotation/sweep, zero-angle crossing, minor/major arcs and
declared full circles; curvature/heading integration; phase-limited quadrature;
spiral chord-deviation lower bounds, stationary root refinement and budget;
positive-left cross product and inverse left normal; incoming-segment shared
boundaries and sharp/disconnected ambiguity; station-equation shifts, limits,
gaps/overlaps; and normal forward/inverse round trips.

One concrete additional defect was found: `StationingEngine.location` applied an
explicit branch after `resolve` had already deduplicated geometric locations.
A zero-jump equation (same back/ahead station) thus rejected its valid ahead
branch; close overlap branches could also disappear. The fix builds raw branch
locations and selects an explicit branch before deduplication. Public unresolved
resolution still deduplicates using the configured station tolerance. A new
zero-jump back/ahead regression and custom-overlap test demonstrate the fix.

No other concrete correctness defect was identified in the reviewed algorithms;
projection/sweep/quadrature/search formulas were retained. Existing 616-case
normal round trips, equation round trips, analytic-circle and 1e-10 Fresnel
benchmarks still pass. Round trips remain limited to unique normal projections;
endpoint longitudinal residuals, overlaps and nonunique normals are documented.
This audit is not a formal proof or independent ORD certification.

## 8. Files modified or added

```text
README.md
PHASE1_REPORT.md (historical report pointer only)
PHASE1_MACOS_AUDIT.md
RoadStation/CLI/main.swift
RoadStation/Core/Geometry/AlignmentEngine.swift
RoadStation/Core/Geometry/CircularCurveGeometry.swift
RoadStation/Core/Geometry/GeometryUtilities.swift
RoadStation/Core/Geometry/LineSegmentGeometry.swift
RoadStation/Core/Geometry/SpiralGeometry.swift
RoadStation/Core/Geometry/StationingEngine.swift
RoadStation/Core/LandXML/LandXMLAlignmentParser.swift
RoadStation/Core/Models/Alignment.swift
RoadStation/Core/Models/AlignmentSegment.swift
RoadStation/Core/Validation/AlignmentValidationCase.swift
RoadStation/Core/Validation/ValidationExporter.swift
RoadStation/Core/Validation/ValidationRunner.swift
RoadStation/Core/Validation/ValidationSummary.swift
Tests/Fixtures/References/README.md
Tests/LandXMLParserTests.swift
Tests/StationEquationTests.swift
Tests/TolerancePropagationTests.swift
Tests/ValidationTests.swift
Validation/ORD-validation-template.json
Validation/ORD-VALIDATION-PROCEDURE.md
Validation/REFERENCE-FIXTURE-AUDIT.md
```

All reference XML bytes and license files remain unchanged.

## 9. ORD direction-convention regression

Default east-origin/counterclockwise direction interpretation and explicit
north-counterclockwise/north-clockwise alternatives are preserved. No curve
rotation inversion was made. The new test reads the first Line's actual `dir`
from `References/cw_reverse_curve.xml`, converts its direction using the default
convention, independently derives heading from NE-to-XY converted endpoints,
and compares the following CCW curve tangent at PC.

Measured headings in radians:

- XML direction and converted internal heading: 0.57886799488641405
- Endpoint-derived line heading: 0.5788679948862419
- Curve PC tangent heading: 0.578867994886408

Largest pairwise discrepancy is approximately 1.73e-13 radians; regression
threshold 1e-11 radians. The test passes in debug and release. Segment count and
length assertions remain as additional importer checks.

## 10–13. Reference inspection and genuine-versus-synthetic evidence

See the [complete fixture audit](Validation/REFERENCE-FIXTURE-AUDIT.md) for every
source, exporter/version, alignment, units, full CRS metadata and exact diagnostics.

| File | Classification | Alignments / units | Line / curve / spiral / equation counts | Parser result |
| --- | --- | --- | --- | --- |
| cw_reverse_curve.xml | Real ORD export-derived regression, translated/stripped; original source DGN absent | ML / US survey feet | 3 / 2 / 0 / 0 | Imports; empty CgPoints scope warning |
| sr82_synthetic.xml | Synthetic | SR 82 / US survey feet; Mississippi East NAD83(2011), EPSG metadata 6507 | 3 / 2 / 0 / 0 | Imports; empty CgPoints scope warning |
| civil3d-road-minimal.xml | Synthetic Civil 3D-labelled | Road A / meters | 1 / 1 / 1 / 0 | Rejects contradictory spiral End; residual 0.0051737917723765695 |
| gis-multiple.xml | Synthetic generic GIS | First, Second / international feet | 2 / 0 / 0 / 0 | Imports; Surfaces scope warning |

All other reference files lack CRS metadata. Mathematical line/circle/Fresnel
checks are **independent numerical checks**, but not independent ORD comparison.
Exporter regression, synthetic fixture and numerical benchmark are distinct.

**Real ORD spiral validation: MISSING**

**Real ORD station-equation validation: MISSING**

No checked-in real/export-derived ORD file contains either. No fabricated
expected values were added, and no synthetic file was relabelled as ORD evidence.

## 14. Backward-compatible validation workflow and template

The original JSON-array case schema and signed positive-left offsets remain
valid. Optional fields add `referenceSoftware`, `referenceSoftwareVersion`,
`sourceLandXML`, `description`, `category`, `inputSide`, `expectedSide`, and
forward `equationSide`. Existing `referenceSource` retains source/revision/report
notes and `branchIndex` chooses inverse equation branches. Coordinates remain
`x=Easting, y=Northing`. Required numeric comparison tolerances remain per case.

An explicit LT/RT/ON side pairs with a nonnegative magnitude; omitted side means
a signed offset as before. Forward side comparisons classify an offset within
`offsetTolerance` as ON to accommodate report rounding (the engine still uses
its own geometry coordinate tolerance). Explicit forward equation-limit cases
require exactly one equation within stationTolerance, select its back/ahead
label, and preserve the projected station residual. General stationing is
unchanged. Both behaviors have positive/negative regression coverage.

JSON/CSV retain the new metadata and actual side. CLI prints case/pass/fail totals,
maximum absolute station/offset errors, maximum Euclidean coordinate error and
counts by supplied category. Missing metrics print N/A; failed cases remain in
counts/maxima where numeric differences exist. No separate reporting system.

`Validation/ORD-validation-template.json` has **32 unpopulated cases**, paired
forward/inverse slots for all 16 requested locations: tangent midpoint zero,
tangent LT/RT, PC/curve midpoint/PT, TS/entry midpoint/SC, CS/exit midpoint/ST,
and immediately before/back/ahead/immediately after an equation. Coordinates
and expected numbers are null; metadata has explicit placeholders. Proposed
0.001 source-unit comparison tolerances are marked for confirmation. Missing
real spiral/equation data is recorded on those cases. Only completed cases should
be copied to a runnable collection JSON. The untouched template fails every case.

## 15–17. Human collection instructions and remaining gate

The [ORD procedure](Validation/ORD-VALIDATION-PROCEDURE.md) gives the practical
steps and verified Bentley command references. Collect a matching unchanged XML
and DGN revision, increase report precision, use horizontal plan coordinates,
obtain precise named points, use Analyze Point for forward station/offset and
Civil AccuDraw Station/Offset for inverse point placement. Record actual ORD
Easting/Northing, station, offset magnitude/side, alignment, source/software
version and report. Keep at least six decimal places, preferably eight/full
precision; retain original labels and zero-based equation branch notes.
**Every expected value must come from ORD independently of RoadStation.**

To run a completed collection from the repository root:

```sh
swift run roadstation-validate Validation/your-real-export.xml \
  Validation/ORD-collected-cases.json validation-output/ord-comparison
```

Remaining blockers: independently recorded ORD forward/inverse answers; source
DGN/report matching the XML coordinate frame/revision; genuine clothoid and
station-equation exports; engineer review of complete comparison coverage. The
local-origin fixture cannot be compared directly with untranslated project
coordinates. More original source data is needed; none was fabricated here.

Phase 1 is technically ready for this human comparison. It has not passed the
external numerical-validation gate. Do not begin Phase 2.
