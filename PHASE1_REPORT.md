# RoadStationCore Phase 1 report

Validated on October 2, 2026, on Windows x86_64 with Swift 6.4. The user's updated
scope is the cross-platform core package. No RoadStationApp, Xcode project or iOS
UI was created; no Phase 2 features were implemented. The package and executable
build successfully, and all **122 XCTest tests pass in debug and release**.

## 1. Files created or modified

The repository initially contained only LICENSE. Phase 1 adds the following
sources and support files; LICENSE is unchanged. An in-progress user commit
captured some early files, so Git now reports both modifications and additions.
Build outputs are ignored and not part of the source inventory.

```text
Package.swift
.gitignore
IMPLEMENTATION_PLAN.md
README.md
PHASE1_REPORT.md
.github/workflows/core-tests.yml

RoadStation/Core/Models/
  ProjectCoordinate.swift
  Project.swift
  Alignment.swift
  AlignmentSegment.swift
  StationEquation.swift
  StationOffsetResult.swift

RoadStation/Core/LandXML/
  XMLDocument.swift
  LandXMLParser.swift
  LandXMLAlignmentParser.swift
  LandXMLParsingError.swift

RoadStation/Core/Geometry/
  GeometryError.swift
  GeometryUtilities.swift
  LineSegmentGeometry.swift
  CircularCurveGeometry.swift
  SpiralGeometry.swift
  ClothoidQuadrature.swift
  StationingEngine.swift
  StationFormatter.swift
  OffsetEngine.swift
  AlignmentEngine.swift
  SegmentBounds.swift
  AlignmentSampling.swift

RoadStation/Core/Validation/
  AlignmentValidationCase.swift
  ValidationRunner.swift
  ValidationExporter.swift

RoadStation/CLI/main.swift

Tests/
  TestSupport.swift
  LineGeometryTests.swift
  CurveGeometryTests.swift
  SpiralGeometryTests.swift
  StationEquationTests.swift
  StationOffsetTests.swift
  InverseStationOffsetTests.swift
  RoundTripGeometryTests.swift
  LandXMLParserTests.swift
  ValidationTests.swift
  SegmentBoundsTests.swift
  AlignmentSamplingTests.swift
  PerformanceTests.swift

Tests/Fixtures/
  .keep
  tangent-only.xml
  simple-curve.xml
  tangent-curve-tangent.xml
  spiral-curve-spiral.xml
  station-equations.xml
  multiple-alignments.xml
  malformed.xml
  validation-cases.json
  References/
    cw_reverse_curve.xml
    sr82_synthetic.xml
    civil3d-road-minimal.xml
    gis-multiple.xml
    README.md
    GIS-LICENSE.txt

tools/
  Test-Windows.ps1
  Generate-SpiralFixture.py
```

Local ignored validation artifacts are available in validation-output/:
analytic.json/.csv, release-analytic.json/.csv, and intentional-failure.json/.csv.
Debug/release test logs are in .build/last-test.log and .build/release-test.log.

## 2. Architecture summary

Package **RoadStationCore** exports a library product of the same name and the
`roadstation-validate` CLI. Its 25 core Swift files contain only Foundation and
conditional cross-platform FoundationXML imports. There are no package
dependencies, Apple-only frameworks, backend or runtime UI assumptions.

Validated immutable `Sendable` models contain planar coordinates, typed segment
geometry, cumulative horizontal distance, station equations, source metadata,
units and import warnings. Models are built once and reused across queries.
The future RoadStationApp can link the library and use public parser, engine,
stationing, validation, sampling and bounds APIs. Display sampling is isolated
from calculation, and a transformer protocol reserves an external CRS boundary
without implementing transformations.

## 3. Supported LandXML elements

LandXML versions 1.0/1.1/1.2; namespaced `Units`, `Metric`/`Imperial`, `Project`,
`CoordinateSystem` metadata, `Alignments`, multiple `Alignment`, ordered
`CoordGeom`, `Line`, circular `Curve`, explicit clothoid `Spiral`, `Start`,
`Center`, `End`, `PI`, and `StaEquation`.

N E [Z] coordinate text is explicitly converted to X=E, Y=N. Import retains
numeric source units, identifying attributes and optional elevation metadata.
Neighbor continuity and declared lengths are checked. Unsupported horizontal
geometry stops import; unrelated profiles/surfaces are not computed. Curve and
spiral parameter contradictions are errors rather than endpoint adjustments.
Direction attributes have explicit import conventions and units; the supplied
ORD fixture convention defaults to east/counterclockwise.

## 4. Exact station/offset approach

Cached conservative segment bounds prune impossible candidates. Lines use exact
clamped dot-product projection. Circular curves use exact radial projection
restricted to their directed sweep plus endpoint comparison. Clothoids use the
bounded numerical search below. Candidates are compared globally.

The winning segment's local arc length plus its cumulative start distance gives
continuous geometric distance. StationingEngine separately maps it to displayed
station. Offset is `cross(unitTangent, query-nearestPoint)`: positive LT, negative
RT. The inverse locates the displayed-station branch and adds signed offset along
the left normal `(-t.y,t.x)` to the exact/numerically integrated centerline point.

Results retain nearest segment/type, point, bearing clockwise from north,
Euclidean distance, longitudinal residual and nearest-location ambiguity. The
inverse result includes resolved station branch. Offset normals at sharp
corners, overlapping stations and distant normal intersections are not silently
assumed unique. Beyond-endpoint points have a longitudinal component that two
station/offset parameters cannot reproduce; this is documented and tested.

## 5. Exact spiral implementation approach

Clothoids use linear signed curvature and its quadratic heading integral:
`k(s)=k0+(k1-k0)s/L`, `theta(s)=theta0+k0*s+(k1-k0)s²/(2L)`.
Position integrates cosine/sine of heading with adaptive Gauss-Legendre 4/8-point
quadrature and phase-limited panels. Cached panel positions reduce per-query
integration work. No coarse polyline answer or endpoint warping is used.

Closest-point search uses phase bracketing and global interval subdivision. The
K*h²/8 curvature bound on deviation from each chord supplies a conservative
query-distance lower bound. Safeguarded gradient-root bisection refines local
perpendicular candidates; finite endpoints always compete. Numerical tolerance
and iteration budgets control convergence and return errors on exhaustion.

Entry/exit, clockwise/counterclockwise, finite-to-finite, constant and zero
curvature are supported. Independent Fresnel benchmarks and reversal identities
verify position/tangent, with dense-search and full-segment-search cross-checks
for nearest point and bounds pruning.

## 6. Station-equation handling

`staInternal - staStart` becomes geometric distance. Sorted equations validate
their back station against the preceding branch. Missing staBack is derived.
Each branch has slope +1 and its own displayed-station shift. Exactly at an
equation, forward station defaults to ahead; callers can explicitly request back.
Both endpoint labels are recognized on inverse lookup.

Inverse resolution returns unique, ambiguous candidates, or outside/gap. Ambiguous
inverse calls throw unless the caller chooses a branch index. Multiple ahead/back
equations, immediate limits, endpoint labels and overlap/gap behavior are tested.
ULP-based endpoint rounding fixes cancellation without replacing mathematical
discontinuities with engineering-tolerance intervals. Formatting remains separate
from numeric station values.

## 7. Test results

| XCTest suite | Tests |
| --- | ---: |
| AlignmentSamplingTests | 4 |
| CurveGeometryTests | 13 |
| InverseStationOffsetTests | 8 |
| LandXMLParserTests | 27 |
| LineGeometryTests | 9 |
| PerformanceTests | 2 |
| RoundTripGeometryTests | 10 |
| SegmentBoundsTests | 5 |
| SpiralGeometryTests | 13 |
| StationEquationTests | 9 |
| StationOffsetTests | 13 |
| ValidationTests | 9 |
| **Total** | **122** |

Debug: **122 passed, 0 failures**, approximately 2.19 seconds test execution.
Release: **122 passed, 0 failures**, approximately 1.82 seconds test execution.
Both test commands compile the library, tests and CLI successfully.

Round-trip suites check 616 deterministic station/offset combinations across
eight alignment configurations, plus branch-aware equation cases and an explicit
endpoint-residual limitation. Offset set: 0, ±5, ±10, ±25. Normal round trips
require 2e-6 project units; supplied projected fixtures require 1e-5. Independent
Fresnel positions require 1e-10. Tests compare actual numbers, not non-null output.

Observed workload timings (this machine, informational rather than CI thresholds):

| Workload | Debug | Release |
| --- | ---: | ---: |
| 300 lines, 2,000 forward queries | 0.180 s | 0.0043 s |
| 300 mixed segments, 1,000 inverse + forward queries | 0.337 s | 0.0145 s |

CLI integration verified debug and release analytic cases (2/2 PASS), independent
Python JSON/CSV reading of exported values, incorrect-reference FAIL exit 1, and
malformed XML import exit 2. `git diff --check` passed. These incorrect inputs
were intentional negative checks; the automated tests all pass.

macOS/Linux CI is configured but not executed locally. Minimum Swift 6.0 is
declared; the locally executed toolchain is 6.4. No Apple SDK or iOS build result
is claimed. Reference fixture imports are regression evidence, not independent
ORD/Civil 3D station-offset certification.

## 8. Known limitations

No CRS projection, GPS/GNSS, native app screens, persistence, MapKit, photos or
Phase 2 features. Horizontal 2D geometry only; no vertical-profile stationing or
computed offset elevations. Unit conversions are deliberately absent. Explicit
direction conventions are necessary for exporter variants. Import uses targeted
validation rather than full XSD compliance. Very large/looping spirals are bounded
by numerical budgets. Normal-coordinate round trips require unique nearest
locations within a usable normal neighborhood.

Malformed XML fails safely, though Foundation's underlying XML error text can
include a platform error-domain/code. Extremely ill-conditioned or nearly equal
nearest solutions can be flagged ambiguous or fail numerical budgets.
Case input is JSON; CSV is export only. External reference values must be supplied
by the user/engineering validation workflow.

## 9. Encountered constructs not supported

The supplied GIS references contain **Surfaces/TIN**, **Profile/ProfAlign/PVI/
ParaCurve**, **CrossSects**, **CgPoints**, and styling `Feature/Property` extensions.
These are outside the horizontal engine and are not calculated. The synthetic
Civil 3D-labelled clothoid has an inconsistent End and is deliberately rejected
as malformed Spiral; its approximate GIS endpoint correction was not adopted.

Additional explicitly rejected cases: non-clothoid/undeclared spiral types,
non-arc Curve, IrregularLine and other horizontal elements, pntRef coordinate
references, multiple CoordGeom per alignment, decreasing staIncrement,
unsupported direction units (including encoded DMS), impossible or ambiguous
center derivation, and invalid station equations. Specialized railway KM-post
equations are not supported. No genuine valid non-clothoid export was encountered
in the supplied fixtures; unsupported examples are also exercised synthetically.

Fixture provenance and license notices are preserved in
Tests/Fixtures/References/README.md and GIS-LICENSE.txt. Core implementation does
not reuse reference project's parser or approximate geometry code.

## 10. Recommended next steps

1. Populate the JSON harness with independently exported ORD/Civil 3D forward and
   inverse results. Cover TS/SC/CS/ST, PC/PT, equation limits/overlaps, direction
   conventions, feet/meters and realistic projected coordinate magnitudes.
2. Run the configured macOS/Linux package checks and build a future RoadStationApp
   on macOS that imports this library. App screens remain future native work.
3. Only after external numerical validation, plan Phase 2's separate CRS adapter,
   MapKit display and CoreLocation/external-GNSS inputs. Keep projected geometry
   independent of those platform services. No Phase 2 implementation has begun.
