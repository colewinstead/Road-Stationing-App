# RoadStation

RoadStation is a native iPhone roadway-stationing project built around a
platform-independent Swift core. The current implementation imports LandXML
horizontal alignments and performs planar station/offset calculations for lines,
circular curves, clothoid spirals and station equations.

The repository currently has seven development milestones:

- **Phase 1 — RoadStationCore:** portable calculation engine, LandXML parser,
  validation CLI and core test suite.
- **Phase 1.5 — RoadStationApp developer harness:** native SwiftUI app for
  LandXML import, alignment selection, engineering-canvas inspection, tap
  queries and manual forward/inverse station-offset queries.
- **Phase 2A — CRS architecture:** portable CRS models and an Apple-only NGA
  PROJ adapter with explicit axis/unit handling and transformation tests. See
  [PHASE2_CRS_REPORT.md](PHASE2_CRS_REPORT.md).
- **Phase 2B — live field position:** explicit project EPSG confirmation/selection,
  foreground When In Use CoreLocation, freshness/accuracy status and the existing
  station/offset engine. See [PHASE2B_LOCATION_REPORT.md](PHASE2B_LOCATION_REPORT.md).
- **Phase 2B.1 — CRS picker:** searchable EPSG metadata, nationwide State Plane
  browse and one-shot location recommendations with explicit confirmation.
  Advanced manual EPSG remains available. See
  [PHASE2B1_CRS_PICKER_REPORT.md](PHASE2B1_CRS_PICKER_REPORT.md).
- **Phase 2B.2 — saved projects (implementation complete):** local SwiftData metadata and project-owned
  original LandXML, cold-start reopen, confirmed CRS/provenance and stable alignment
  restoration, rename, confirmed deletion and staged source replacement. See
  [PHASE2B2_SAVED_PROJECTS_REPORT.md](PHASE2B2_SAVED_PROJECTS_REPORT.md).

- **Phase 2C — MapKit:** satellite by default, street-map switching, geographic
  alignment/snapshot overlays and a local engineering-grid fallback inside Field
  Position. See [PHASE2C_MAPKIT_REPORT.md](PHASE2C_MAPKIT_REPORT.md).

The Phase 1.5 app has been built and tested in the iPhone Simulator and has also
been installed and launched successfully on a physical iPhone using Xcode
automatic signing.

**RoadStation is not surveying software.** Field Position uses foreground phone
location after explicit CRS confirmation. It shows GPS accuracy and withholds
new calculations from stale/invalid fixes while retaining an explicitly labeled
last-known snapshot during an active session. Physical-device field validation is still needed. MapKit display is implemented; geographic
field placement is not yet physically verified. Local saved projects are implemented; physical-device
lifecycle testing remains required.

A real OpenRoads Designer validation dataset is checked in under
[Validation/RealORD/CROSSGATES](Validation/RealORD/CROSSGATES/README.md). It
contains a direct ORD LandXML export, horizontal/vertical reports, station-offset
reference data and independent validation cases covering real tangents, CW/CCW
curves, clothoid spirals, LT/RT offsets and a station equation. The comparison
passed **30/30 cases** at **0.001 US survey foot** tolerance. Phase 2A
preserves that geometry and tolerance.

## Architecture

```text
Package.swift                         RoadStationCore + harness-support package
RoadStation/Core/
  Models/                             Project, alignment, segments, coordinates, results
  CRS/                                Portable CRS identities, readiness, errors, protocol
  LandXML/                            XML boundary, typed alignment builder, import errors
  Geometry/                           Lines, arcs, clothoids, stationing, offsets, bounds
  Validation/                         JSON cases, runner, JSON/CSV results
RoadStation/CLI/                      roadstation-validate command
RoadStationApp/
  RoadStationApp.xcodeproj/           Native iPhone Xcode project
  RoadStationApp/                     SwiftUI developer harness
  HarnessSupport/                     Viewport/manual-query helpers
  HarnessSupportTests/                Helper tests
  CRSAdapter/                         Apple CRS/catalog/field-position/saved-project packages
  RoadStationAppUITests/              Simulator UI tests
Tests/                                Core XCTest suites and fixtures
Validation/
  RealORD/CROSSGATES/                 Real ORD source data and validation cases
tools/Test-Windows.ps1                Windows build/test helper
tools/Test-iOS-Harness.sh             Simulator UI-test helper
tools/Generate-CRS-Catalog.py          Repeatable metadata extraction from NGA proj.db
.github/workflows/core-tests.yml      Core/Apple checks + iOS build, unit and full UI tests
```

Parse once, then query immutable, validated, `Sendable` models. Segment start/end
distances are cumulative **horizontal geometric length**, independent of station
equations. Typed `SegmentGeometry` cases contain validated lines, circular arcs,
or clothoids. Raw XML attribute dictionaries remain inside the import boundary.
Alignment metadata preserves name, source identifier, description and declared
length. Project metadata retains units and a CRS description. Explicit LandXML
`epsgCode` identifies a CRS; absent or invalid identification stays unresolved.
Import never transforms the geometry. Disconnected neighbors produce warnings and keep their
original geometry; gaps do not count as geometric length.

The checked-in **RoadStationApp** Xcode project links this repository as a
local Swift package and uses the **RoadStationCore** library product directly:

```swift
import RoadStationCore
import Foundation

let project = try LandXMLParser().parse(url: xmlURL)
let alignment = project.alignments[0] // App should offer alignment selection.
let engine = AlignmentEngine(alignment: alignment)
let result = try engine.stationOffset(
    point: ProjectCoordinate(x: 2456789.123, y: 987654.321)
)
let text = result.formattedStation
let coordinate = try engine.coordinate(
    station: result.displayedStation, offset: result.signedOffset
).coordinate
```

The app owns file access, project persistence, screens and interaction. SwiftData
stores lightweight project metadata; an app-owned copy of the original LandXML
is reparsed on each open. Geometry is never serialized into the database.
Confirmed CRS and the last alignment are restored without starting location.
Public
`AlignmentSampling.polylines` and segment bounds support a future engineering
canvas without introducing a UI dependency. Samples are for display only and
keep disconnected segments separate. Forward/inverse math never uses them.
`ProjectCoordinateTransformer` lives in the portable core; the Apple-only
`RoadStationApp/CRSAdapter` package implements it with NGA PROJ. Core dependencies
remain unchanged. Geographic degree output must not enter the planar engine.

## Supported LandXML

- LandXML 1.0/1.1/1.2, namespace-aware parsing (default or prefixed namespace).
- `Units/Metric`, `Units/Imperial`, `Project`, `CoordinateSystem` metadata.
- Multiple `Alignments/Alignment` elements; `name`, `length`, `staStart`,
  `desc`/`description`, `oID`/`id` metadata.
- One ordered `CoordGeom` per alignment, with `Line`, `Curve`, `Spiral`.
- Inline `Start`, `End`, `Center`, `PI` as N E or N E Z.
- Circular `Curve`: explicit `rot=cw|ccw`, radius or derivation from Center;
  center can be derived from endpoints + radius + length when unique.
  Minor/major arcs, angular-zero crossing and declared full circles are supported.
- Explicitly declared `spiType=clothoid`; positive `length`, `radiusStart` and
  `radiusEnd` (positive radius or `INF`), `rot`, and `PI` or `dirStart`.
  Optional `dirEnd` is checked against the curvature law.
- `StaEquation`: `staInternal`, `staAhead`, optional `staBack`, increasing
  stationing. Missing back station is derived from the preceding branch.

Line lengths are checked against horizontal coordinate distance. Arc lengths are
checked against radius and directional sweep. A contradictory curve orientation
or clothoid endpoint is an import error. Declared alignment length differences
produce warnings. File size, XML nesting, node and expanded-text limits are
enforced; external resolution is disabled and entity declarations are rejected.
This is targeted horizontal parsing, not complete XSD validation.

### Coordinate and direction conventions

Internal coordinates are **X=Easting, Y=Northing, optional Z=Elevation**.
`LandXMLParser.coordinate(from:)` explicitly converts LandXML's **Northing
Easting [Elevation]** order at import. Tests use unequal coordinates to catch
accidental reversal. No implicit scaling, translation, or unit conversion occurs.

Internal mathematical heading is counterclockwise from east. Internal clockwise
curvature is negative; counterclockwise curvature is positive. Swapping the NE
axes reverses angle handedness, so reference code written in NE coordinates
cannot have its rotation sign copied directly into XY calculations.

The supplied ORD examples have `dir=0` on eastbound lines. Accordingly, the
default **direction attribute interpretation is east/counterclockwise**. LandXML
exchange conventions vary (the buildingSMART profile documents north-origin
directions). Set `LandXMLParserOptions.directionConvention` explicitly to
`.northCounterclockwise` or `.northClockwise` for those files. Direction units
support radians (default), decimal degrees and grads/gon; encoded DMS is not
supported. PI coordinates define the initial spiral tangent when supplied, and
conflicting direction data is rejected. Line tangents come from endpoints and
arc tangents from geometry, not optional direction attributes. The returned
`bearing` is always **clockwise from north in radians [0, 2π)**.

Reference: [buildingSMART LandXML alignment profile](https://buildingsmart.fi/infra/bSI_LandXML12_MVD/pages/3_Alignments.html).
Source-file exporter labels alone are not proof of external numerical validation.

### Units and elevation

`ProjectUnit` distinguishes meter, international foot, US survey foot and unknown.
`foot` is retained as international foot; `USSurveyFoot` is distinct. Unknown or
other units produce a warning and retain numeric values. All lengths, stations,
offsets, tolerances and coordinates must share the source project's linear unit.
All calculations are **2D**. Z is retained/interpolated between supplied endpoint
elevations as metadata; it is not a vertical-profile or slope-distance solution.
Offset coordinates intentionally have no computed elevation.

## Exact station/offset approach

1. Sort cached segment boxes by their lower distance bound to the query; skip
   boxes that cannot improve or tie the best result. No spatial index is needed.
2. A line uses the exact unit-tangent projection, clamped to its finite extent.
3. An arc uses the radial projection if its directed angle is within the arc,
   otherwise compares finite endpoints. Centers and equal-distance candidates
   carry ambiguity flags. Circular math is analytic, not polyline based.
4. A clothoid uses the bounded numerical nearest-point search below.
5. Compare candidates globally. Add the winning local distance to the segment's
   cumulative start distance, then apply the station-equation mapping.

For a unit tangent `t` and vector `v = query - nearestPoint`, signed offset is
`cross(t, v) = t.x*v.y - t.y*v.x`. **Positive = LT; negative = RT**. The inverse
adds `offset * (-t.y, t.x)` to the centerline point. East/west/north/south/NE/SW
tests verify orientation independently of any screen view.

The forward result includes numeric/formatted station, geometric distance,
signed offset, side, nearest point, zero-based segment index/type, tangent,
bearing, Euclidean query distance, longitudinal residual and ambiguity flag.
Ties at different geometric locations or incompatible tangents are explicitly
marked. A deterministic representative is returned for inspection; callers
must heed `nearestLocationIsAmbiguous` before assuming a unique solution.

Inverse station/offset returns a coordinate and its resolved equation branch.
At a smooth shared boundary it uses the incoming segment. A sharp corner or
disconnected boundary has no unique offset normal; forward queries flag tied
incompatible candidates. Large offsets can cross a curve's center of curvature
or reach a different alignment segment. Such coordinates need not project back
to the requested station. Tests use offsets within a uniquely defined normal
neighborhood.

Endpoint-clamped projections can contain a **longitudinal residual**. Station
plus perpendicular offset has only two parameters tied to a fixed endpoint
normal and cannot reconstruct a point beyond that normal. Round-trip guarantees
apply to unique normal projections, not endpoint extensions, overlaps, corners
or self-intersections. This limit is explicitly tested.

## Station equations and formatting

Geometric distance begins at zero and is continuous. Displayed station can jump.
For import, `geometricDistance = staInternal - alignment.staStart` (unequated
station). Equations are sorted, validated within alignment limits, and their
back station is checked against the preceding branch. Decreasing `staIncrement`
and specialized railway KM-post semantics are unsupported.

On each branch displayed station is `distance + branchShift`. An equation
changes that shift to `stationAhead - equationDistance`. Exactly at the equation
the default is **ahead**; `station(at:equationSide: .back)` exposes the back label.
Values immediately before/after remain on their respective branches.

`resolve(station:)` returns `.unique`, `.ambiguous([StationLocation])`, or
`.outsideAlignment`. Ahead jumps create station gaps; back jumps create overlaps.
Both back/ahead endpoint labels are recognized. `coordinate(station:offset:)`
throws on ambiguity unless an explicit zero-based `branchIndex` is supplied.
ULP-sized rounding bounds handle subtraction at branch endpoints without
swallowing engineering-scale gaps.

`StationFormatter` keeps the underlying station numeric. Examples: 42738.42 →
427+38.42, 125 → 1+25.00, 0 → 0+00.00. Precision is configurable from 0 to 6
decimal places, with rounding/carry and negative station handling. `parse` accepts
numeric station or major+minor text; major intervals are 100 project units.

## Spiral methodology

Euler/clothoid signed curvature is linear in arc length:

```text
k(s) = k0 + (k1-k0)*s/L
theta(s) = theta0 + k0*s + (k1-k0)*s²/(2L)
p(s) = p0 + integral_0^s (cos(theta(u)), sin(theta(u))) du
```

This handles entry, exit, finite-to-finite curvature, either rotation, and the
constant/zero-curvature limits. Spiral positions are integrated using adaptive
Gauss-Legendre 4-versus-8-point quadrature. Initial panels limit tangent change
to at most 0.2 radians to prevent oscillatory aliasing. Cached panel integrals
avoid reintegrating from the beginning for each query. Tangents use the exact
curvature integral. There is **no endpoint warp or positional correction**.

Nearest-point search begins with phase-aware bracketing (at least 16 intervals).
For each interval of arc length h with |curvature| ≤ K, curve deviation from its
chord is bounded by K*h²/8. Chord distance minus this deviation is a lower bound
on distance to the interval. Intervals that could improve/tie the best candidate
are subdivided. Safeguarded bisection refines stationary perpendicular candidates
using `(p(s)-query)·t(s)=0`; endpoints are always considered. Search stops on the
distance bound or interval convergence tolerance. Quadrature and search budgets
throw meaningful errors rather than silently returning an unconverged answer.
Near-degenerate/equal minima are flagged where detected; there is no claim that
station/normal uniqueness holds at evolutes or pathological looping spirals.

Independent benchmarks use a Fresnel power series and the exit-spiral reversal
identity. Constant-curvature results are compared with analytic circles. Dense
evaluation cross-checks the nearest-point search, and a full segment search
cross-checks bounds pruning.

## Numerical tolerances

`GeometryTolerances` centralizes positive finite tolerances. Defaults are in
project units: coordinate/station/tie/closest-point 1e-7, integration 1e-10,
continuity/import consistency 0.001. Angle comparison is 1e-10 radians; approximate
nearest-solution tangent ambiguity uses 1e-8 radians. Tolerances can be
configured in parser options or geometry constructors and remain attached to the
immutable geometry. An alignment inherits a shared geometry context when omitted;
mixed contexts require an explicit `tolerances:` override, which revalidates all
segments and rebuilds spiral caches. Alignment/query engines use that same context.
`checkedDistance` requires an explicit tolerance, preventing silent fallback. Quadrature also has a floating-point roundoff floor.
Round-trip tests require 2e-6 project units (1e-5 for supplied large projected
examples). Independent position benchmarks require 1e-10 project units.
Tolerance defaults are engineering assumptions, not external certification.

## Running builds and tests

Requires Swift 6.0 or later. No package dependencies or backend are needed.

```sh
swift build
swift test
swift test -c release
```

On Windows, install the [official Swift toolchain and its C++/Windows SDK prerequisites](https://www.swift.org/install/windows/).
Run from PowerShell:

```powershell
.\tools\Test-Windows.ps1
.\tools\Test-Windows.ps1 -Release
```

The script locates Swift, reads the installer-provided user SDKROOT, loads the
Microsoft native x64 build environment, and adds Swift runtime DLLs to this
process's PATH. It also leaves that environment available for `swift build` and
`swift run` in the same PowerShell session. A newly opened terminal may already
have the installer environment. The script does not alter machine settings.

This implementation was originally compiled and tested on Windows with Swift 6.4.
The macOS Phase 1 audit and local debug/release results are recorded in
[PHASE1_MACOS_AUDIT.md](PHASE1_MACOS_AUDIT.md). Phase 1.5 is documented in
[PHASE15_REPORT.md](PHASE15_REPORT.md). CI covers the macOS/Linux core package
matrix, CROSSGATES, Apple field-position/CRS tests, an iOS Simulator build and the
explicit CRS/injected-position UI flow. The Phase 1.5 app has also been installed and
launched on a physical iPhone. Production/App Store distribution and live GPS
behavior remain unverified. Phase 2A CRS tests pass on macOS and iOS Simulator.
Swift 6.4 Windows
may emit an ignored root Info.plist for XCTest resources and a warning about its
.build/debug convenience symlink; these are build-tool artifacts.
## Validation harness and adding cases

Cases are stored as a JSON array of `AlignmentValidationCase`; numeric station,
positive-left signed offset, coordinates and explicit tolerances are required.
`referenceSource` identifies the external application/version or independent
calculation. Use unique alignment names for matching. Case errors are FAIL
results, so a malformed case cannot pass silently. Forward cases with ambiguous
nearest locations fail. Inverse cases can specify `branchIndex` for overlaps.

The checked-in example `Tests/Fixtures/validation-cases.json` contains hand
calculations, **not independently verified ORD/Civil 3D values**. For a right
offset of 24.61, enter `expectedOffset: -24.61` (or `inputOffset` for inverse).
Convert station 425+37.28 to numeric 42537.28, or use `StationFormatter.parse`.

```sh
swift run roadstation-validate Tests/Fixtures/tangent-only.xml \
  Tests/Fixtures/validation-cases.json validation-output/analytic
```

PowerShell equivalent after the test script prepares the environment:

```powershell
swift run roadstation-validate Tests/Fixtures/tangent-only.xml Tests/Fixtures/validation-cases.json validation-output/analytic
```

Optional final arguments: `--directions east-ccw|north-ccw|north-cw`. The command
writes `.json` and `.csv`, prints a summary, and exits 0 for all PASS, 1 for failed
cases, or 2 for usage/import/IO errors. CSV contains input/expected/actual values,
numeric signed differences, Euclidean coordinate difference, tolerances,
reference source and PASS/FAIL. Cases load from JSON; CSV is an **output** format.
Public runner/exporter APIs can later be used by RoadStationApp.

For real ORD collection, use the [step-by-step procedure](Validation/ORD-VALIDATION-PROCEDURE.md)
and [unpopulated forward/inverse template](Validation/ORD-validation-template.json).
Optional fields add software/version, XML filename, feature description, category,
LT/RT/ON magnitudes and explicit forward equation limits; existing signed-offset
JSON remains compatible. Console output includes counts and maximum absolute
station/offset and Euclidean coordinate errors. The
[reference audit](Validation/REFERENCE-FIXTURE-AUDIT.md) distinguishes export-derived
regressions, synthetic fixtures and independent mathematical benchmarks.

### Real ORD validation dataset

A real OpenRoads Designer dataset is available at
[Validation/RealORD/CROSSGATES](Validation/RealORD/CROSSGATES/README.md).
CROSSGATES supplies independent ORD reference data for tangents, LT/RT offsets,
clockwise and counterclockwise circular curves, clockwise and counterclockwise
clothoid spirals, an exit spiral, and a real station equation with explicit
BACK/AHEAD handling. A proposed vertical profile is also retained for future
vertical work.

The expected values were collected from ORD rather than generated by
RoadStationCore. The runnable case file is
`Validation/RealORD/CROSSGATES/CROSSGATES-ord-cases.json`.

Run it from the repository root in PowerShell:

```powershell
swift run roadstation-validate `
  Validation\RealORD\CROSSGATES\CROSSGATES.xml `
  Validation\RealORD\CROSSGATES\CROSSGATES-ord-cases.json `
  validation-output\CROSSGATES
```

The current comparison tolerance is 0.001 US survey foot for station, offset
and coordinate error. Preserve failed cases and investigate source revision,
units, coordinate convention, equation branch and report rounding before
changing tolerances. The Phase 2A regression run passed all 30 cases without
changing source geometry or tolerances. Phase 2B also passes all 30 with the same
case file and tolerance definitions.

## Product roadmap

RoadStation is intended to grow from validated station/offset calculations into a
persistent field-project application. Phase 2B.2 and 2C are implemented; later
stages remain planned:

- **Phase 2B.2 — Saved projects:** persist imported LandXML, confirmed CRS,
  selected alignment and project settings so projects can be reopened without
  re-importing source files. A project may contain multiple alignments.
- **Phase 2C — MapKit:** show imported alignments and live field position on a
  geographic basemap while keeping mapping separate from the validated geometry
  engine.
- **Phase 3 — Field records:** project-linked photos, notes, observations and
  station-stamped reports.
- **Phase 4 — Vertical/profile and surface workflows:** add vertical alignment
  support and, when suitable existing/proposed surfaces are available, evaluate
  grade and cut/fill workflows.
- **Phase 5 — Georeferenced construction plans:** import project construction-plan
  PDFs and use alignment/station information to register roadway plan sheets to
  project coordinates. The goal is to let a field user view the **actual plan
  sheet as the map** and see the phone's current position directly on the
  construction drawing.
- **Phase 6 — Augmented Reality construction model:** import proposed finished-grade
  LandXML surface/TIN data and render the proposed project at **true 1:1 scale**
  through the iPhone camera. RoadStation should register the engineering model to
  the real site using project coordinates, explicit calibration and, where
  appropriate, geographic positioning so a field user can walk the project and
  visualize where pavement, curb, slopes, ditches and other finished-grade
  features will be built.

### Phase 5 concept — construction plans as a field map

A saved project may contain one or more LandXML alignments plus one or more plan
sets. RoadStation should identify plan-view sheets, associate them with relevant
alignment station ranges, and build a sheet-to-project-coordinate transform. For
standard roadway sheets, station labels, match lines and centerline geometry can
provide candidate control information because RoadStation can already convert
station/offset to project Easting/Northing.

The intended workflow is:

```text
Saved project
    ↓
LandXML alignment(s) + construction plan PDF
    ↓
Identify plan sheets / alignment / station ranges
    ↓
Georeference each usable plan view to project coordinates
    ↓
Phone WGS84 → project CRS → Easting/Northing
    ↓
Display live position on the actual construction plan sheet
```

Automatic registration should be attempted where the plan data provides enough
reliable information, but it must not pretend every PDF can be georeferenced from
station text alone. The design should support an assisted fallback where the user
confirms station marks or supplies two or more station/offset control points on
the sheet. Those controls can be converted through the existing alignment engine
to known project coordinates.

Longer-term plan-view behavior may include automatic switching to the next sheet
as the user crosses a match line/station range, multiple alignments on the same
sheet, and optional transparency comparison between georeferenced plans and a
geographic/satellite basemap. Registration quality and control-point provenance
must remain visible; a plan overlay must not be presented as survey-grade merely
because it aligns visually.


### Phase 6 concept — full-scale AR construction model

Phase 6 extends RoadStation from showing the project on a map or plan sheet to
showing the proposed project **in the real world through the camera**. A saved
project should be able to own a proposed finished-grade LandXML surface in
addition to its horizontal alignments. RoadStation would parse the proposed
surface/TIN into engineering-space vertices and triangular faces, preserve its
project CRS and elevation information, and render that mesh through ARKit /
RealityKit at engineering scale.

The intended experience is:

~~~text
Saved RoadStation project
    ↓
Alignment LandXML + proposed finished-grade LandXML/TIN
    ↓
Parse surface points / faces / metadata
    ↓
Project-space 3D surface (Easting / Northing / Elevation)
    ↓
Establish project-to-AR registration
    ↓
Render proposed finished grade at 1:1 scale
    ↓
Walk the site while the proposed roadway remains fixed in the real world
~~~

A field user could stand on an undeveloped or partially built project, open an
**AR View**, and see a translucent representation of the proposed roadway in its
future location. As the user walks, the model should remain fixed relative to the
site rather than moving with the phone. Potential visualization targets include
pavement, curb and gutter, sidewalks, islands, ditches, side slopes, embankments
and other elements represented by the imported finished-grade surface.

The core product promise for this phase is intentionally:

> **Visualize the proposed roadway at full scale in its future location.**

It is not a claim of survey-grade AR stakeout. Rendering a 1:1 model is much
easier than proving that the model is registered to the site with construction
or survey accuracy. RoadStation must keep model scale separate from positioning
accuracy and must show registration quality honestly.

#### Phase 6A — LandXML surface / TIN engine

RoadStation currently validates horizontal alignment geometry and intentionally
does not compute LandXML surfaces. Phase 6 should add a separate surface model
rather than overloading AlignmentEngine.

A proposed structure is:

~~~text
RoadStationCore
    AlignmentGeometry
    SurfaceGeometry
        Surface
        SurfacePoint
        TriangleFace
        SurfaceBounds
        SurfaceMetadata
~~~

The first AR-capable surface implementation should focus on the information
required to reconstruct a proposed TIN:

- surface/project identity and units;
- 3D points in project Easting/Northing/Elevation;
- triangular face connectivity;
- bounds and basic topology validation;
- source metadata and warnings;
- explicit rejection of unsupported or contradictory definitions rather than
  silently inventing geometry.

The imported engineering surface remains authoritative. Rendering code may derive
display meshes, tiled meshes or lower-detail representations, but those display
products must never become the source for engineering calculations.

#### Phase 6B — RealityKit 1:1 rendering

RoadStation should convert the validated project-space TIN into a RealityKit mesh.
ARKit/RealityKit operate in meters, so the renderer must use the project's known
linear unit and perform an explicit conversion:

~~~text
1 project meter = 1 RealityKit meter
1 international foot = 0.3048 RealityKit meters
1 US survey foot = 1200/3937 RealityKit meters
~~~

Large State Plane coordinates must not be placed directly into scene coordinates.
The AR renderer should establish a nearby local project origin and work with
deltas from that origin while preserving full Easting/Northing/Elevation values
in the engineering model.

The first rendering milestone should prove:

- correct 1:1 scale;
- correct axis handedness and East/North/Up orientation;
- stable camera-relative tracking;
- translucent finished-grade rendering;
- clipping and visibility behavior suitable for roadway-scale geometry;
- acceptable performance on a physical iPhone.

Large surfaces will likely require spatial tiling, culling and level-of-detail
strategies so RoadStation does not send an entire multi-mile TIN to the GPU when
the user can only see a small part of the project.

#### Phase 6C — geographic project placement

Where supported and appropriate, RoadStation can use its existing CRS stack to
connect project coordinates to geographic AR placement:

~~~text
LandXML E / N / Z
    ↓
confirmed project CRS
    ↓
PROJ transformation
    ↓
WGS84 latitude / longitude + vertical reference
    ↓
geographic AR placement
~~~

Geographic AR should be treated as a convenience positioning mode, not as proof
that the proposed surface is precisely registered. Availability, GNSS error,
device heading, geographic-tracking support and vertical-reference differences
can all move the displayed model.

The app should therefore show the active positioning source and quality rather
than hiding it. For example:

~~~text
AR Registration
Source: iPhone geographic position
Horizontal accuracy: ±18 ft
Vertical accuracy: ±27 ft
Heading: device estimate
Use: visualization only
~~~

A surface must never be silently shifted to "look right."

#### Phase 6D — engineering control-point calibration

RoadStation's strongest AR positioning method should be explicit engineering
calibration using known project coordinates. Because RoadStation already
understands station/offset and project Easting/Northing, the user can provide
control that generic AR viewers do not have.

Possible control-point workflows include:

~~~text
Stand on known point
    ↓
Choose / enter:
STA 125+00
15.00 ft RT
Elevation 312.44
    ↓
RoadStation resolves project XYZ
    ↓
Associate that XYZ with the current AR world location
~~~

A second known point, or a known backsight/direction, can establish horizontal
orientation. Three or more well-distributed points can support a redundant fit
and residual checks. Calibration should be able to use:

- station + offset + elevation;
- an imported survey/control point;
- a known project coordinate;
- a point selected from a future plan/surface view;
- other explicitly identified engineering control.

The app should retain the distinction between horizontal and vertical
registration and report the evidence used. A calibrated session might show:

~~~text
AR Registration
Horizontal: calibrated
Vertical: calibrated
Orientation: calibrated
Control points: 3
Fit residual: 0.08 ft
~~~

The exact residual model and acceptance thresholds must be defined and validated
before any accuracy claim is made. A low mathematical residual does not by itself
prove that the supplied control coordinates or phone placement were correct.

#### Phase 6E — LiDAR / scene reconstruction and occlusion

On supported devices, AR scene reconstruction can be used to improve visual
integration with the existing site. Reconstructed real-world geometry could
allow existing objects or ground to occlude parts of the proposed model instead
of letting the proposed surface unrealistically draw through everything.

Future experiments may also compare a locally observed scene surface with the
proposed finished-grade surface for visualization. Any such comparison must be
presented as an approximate field aid unless its measurement accuracy has been
independently established; phone LiDAR is not a substitute for survey or
machine-control data.

#### Phase 6F — AR cut / fill visualization

After Phase 4 establishes trustworthy existing-ground and proposed-surface
workflows, AR can visualize the difference at the user's location or across a
visible portion of the model.

Potential modes include:

~~~text
Proposed finished grade
Cut / fill heat map
Pavement-only
Curbs / edges
Ditches / slopes
Existing vs proposed
~~~

A point readout could eventually show:

~~~text
STA 256+42
32.4 ft RT

Existing ground: 314.6 ft
Finished grade: 318.1 ft
Fill: 3.5 ft
~~~

Color or opacity may communicate cut/fill visually, but numeric values must still
come from validated engineering surfaces rather than the rendered mesh.

#### Phase 6G — external RTK GNSS

The architecture should leave room for an external high-accuracy GNSS receiver.
An RTK-capable positioning source could provide project/geographic coordinates
with much better repeatability than ordinary phone location and feed the same
project-to-AR registration layer.

RoadStation should model positioning source and quality explicitly so future
inputs can coexist:

~~~text
iPhone GNSS
Geographic AR
Manual control-point calibration
External RTK GNSS
~~~

The renderer should not care which positioning source produced the accepted
project-to-AR transform. That separation will allow RoadStation to improve field
accuracy later without rewriting the LandXML surface or RealityKit pipeline.

#### Phase 6 registration and safety rules

Phase 6 should preserve the same philosophy already used for CRS and live
stationing:

- never guess a CRS, vertical datum or engineering control point;
- never silently move, rotate or scale the model to make it visually align;
- always keep **1:1 model scale** separate from **registration accuracy**;
- expose positioning source, accuracy and calibration state;
- preserve the original surface and control-point provenance;
- allow recalibration without altering source engineering data;
- reject unsupported surface/vertical definitions rather than inventing them;
- keep AR visualization distinct from survey-grade stakeout unless a future
  workflow is independently validated to support such a claim.

A long-term project directory can accommodate the feature without changing the
saved-project identity:

~~~text
Projects/<UUID>/
    Sources/
        alignment.landxml
        finished-grade.landxml
    Plans/
    PlanRegistration/
    Surfaces/
        derived-render-cache/
    ARRegistration/
        control-points / session metadata
    Photos/
    Reports/
~~~

Derived RealityKit meshes and level-of-detail caches should be reproducible from
the authoritative source surface and may be discarded/rebuilt. Engineering
source files and calibration provenance should remain traceable.

## Known limitations and next gate

- Only explicit clothoids are supported. Bloss, cubic, cosine, sinusoid and
  other transition definitions are rejected, as are undeclared spiral types.
- pntRef, IrregularLine, multiple CoordGeom containers, decreasing station
  branches and unsupported horizontal elements are rejected. No partial geometry
  is silently substituted. Profiles, surfaces, CgPoints, cross sections,
  superelevation and other unrelated datasets are not computed.
- Real exporter direction conventions must be selected explicitly; DMS units,
  survey rotations/translations and nonhorizontal length interpretations are
  not supported. Extremely looping spirals can exceed numerical budgets.
- The synthetic Civil 3D-labelled reference spiral has an inconsistent endpoint
  and is deliberately rejected. It is not an external accuracy benchmark.
- RoadStationApp now keeps local saved projects. It does
  not yet include background location,
  camera/photo workflows, cloud sync or App Store distribution.
- LandXML surfaces/TINs, vertical registration, RealityKit/ARKit construction
  visualization, LiDAR scene reconstruction and RTK positioning are roadmap
  concepts only; none are implemented or validated yet.

Phase 2C adds a read-only MapKit context view for the opened saved project,
using the existing inverse transformer for display samples and keeping stationing
in project space. Validate known points, axis/units and GPS quality on the physical
iPhone before claiming map/field accuracy.
See [PHASE2B_LOCATION_REPORT.md](PHASE2B_LOCATION_REPORT.md) for exact scope and
verification limits.
