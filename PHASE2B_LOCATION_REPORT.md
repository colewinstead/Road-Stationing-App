# RoadStation Phase 2B — location report

Date: 2026-10-03. Baseline: merged Phase 2A `23bfcb3` (PR #3).
Phase 2B provides explicit CRS selection/confirmation and foreground field position.
The validated core geometry, CRS models, Phase 2A production transformer, and
CROSSGATES tolerance definitions are unchanged.

## Architecture and changed files

`RoadStationApp/CRSAdapter` now exposes a separate Apple-only
`RoadStationFieldPosition` product containing:

- `LocationTypes.swift`: injectable samples, permission/status models, selection
  provenance and configurable quality policy.
- `CoreLocationService.swift`: main-runloop CLLocationManager behind
  `LocationProviding`, mapping CLLocation data into immutable sample values.
- `FieldPositionSession.swift`: session-only selection, freshness/accuracy gating,
  transformation/geometry execution and revision-checked results.

The path is CLLocation → LocationSample → GeographicCoordinate → existing
PROJProjectCoordinateTransformer → ProjectCoordinate (Easting/Northing in project
units) → existing AlignmentEngine → StationOffsetResult. Projection and stationing
run on detached tasks. The main actor owns service/selection/publication; each
change or stop invalidates superseded calculation work. A separate CRS-selection
revision prevents location callbacks from canceling validation and prevents an
old validation from publishing after project replacement. No C handles cross threads.

App changes are `FieldPositionView.swift`, `HarnessModels.swift`, `ProjectView.swift`,
`AlignmentWorkspace.swift`, Info.plist and Xcode product/source/test wiring.
Existing canvas and manual tools remain available. New deterministic field tests
share their source between macOS SPM and the iOS RoadStationCRSTests target.
The benchmark executable, CI workflow, UI tests and README files are also updated.
No CoreLocation, MapKit, SwiftUI, Projections or proj imports enter RoadStationCore.

Changed-file inventory (repository-relative):

```text
.github/workflows/core-tests.yml
README.md
PHASE2B_LOCATION_REPORT.md
RoadStationApp/README.md
RoadStationApp/CRSAdapter/Package.swift
RoadStationApp/CRSAdapter/Sources/RoadStationFieldPosition/LocationTypes.swift
RoadStationApp/CRSAdapter/Sources/RoadStationFieldPosition/CoreLocationService.swift
RoadStationApp/CRSAdapter/Sources/RoadStationFieldPosition/FieldPositionSession.swift
RoadStationApp/CRSAdapter/Sources/RoadStationTransformBenchmark/main.swift
RoadStationApp/CRSAdapter/Tests/RoadStationFieldPositionTests/FieldPositionTests.swift
RoadStationApp/RoadStationApp.xcodeproj/project.pbxproj
RoadStationApp/RoadStationApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
RoadStationApp/RoadStationApp/FieldPositionView.swift
RoadStationApp/RoadStationApp/HarnessModels.swift
RoadStationApp/RoadStationApp/ProjectView.swift
RoadStationApp/RoadStationApp/AlignmentWorkspace.swift
RoadStationApp/RoadStationApp/Info.plist
RoadStationApp/RoadStationAppUITests/RoadStationAppUITests.swift
```

The generated Xcode resolution origin hash changes with the package manifest;
dependency versions/revisions remain pinned to the Phase 2A versions.

### Continuous display during location updates

The original callback called `invalidate()` before every calculation. That cleared
the coordinate/result and switched status to Calculating, removing the result rows
and shrinking the card until the new calculation completed.

`FieldPositionSnapshot` now holds the completed station/offset, project coordinate,
matching raw sample/accuracy/timestamp/source, alignment identity/name, confirmed
CRS/provenance, project units, precision, ambiguity/status and projection timing.
It is immutable and equatable at the Apple boundary; no core conformances or math
changed. The session publishes this snapshot once on the MainActor after successful
off-actor calculation. Coordinate/result/timing accessors derive from it.

Calculation activity is a separate `isCalculating` property. An ordinary update
advances the calculation revision without clearing the displayed snapshot. The
card continues showing that snapshot's matching accuracy, age, context and status;
it never combines an old station with a pending fix's metadata. A small update icon
has a permanently reserved frame. The card disables SwiftUI animations and retains
monospaced digits. DEBUG injection scrolling is also unanimated. GPS delivery and
projection/station calculations are not throttled or changed.

Initial calculation can still show Calculating with no result. Stop, project/CRS/
alignment replacement and permission loss deliberately clear the snapshot. Stale,
invalid and failed subsequent updates retain the last successful snapshot, never
masquerading as a new successful result. After 5 seconds it is prominently labeled
**Stale — last known position** with its continually increasing age. The calculation
eligibility threshold is unchanged: stale data cannot start a new transform/station
query or publish a newly computed result. Only a fresh successful result removes
the stale warning and atomically replaces the snapshot.

Freshness presentation is separate from the immutable completed snapshot. Repeated
stale checks neither clear nor republish it. The status area has a fixed height that
scales with Dynamic Type, so fresh → stale → fresh does not resize the card. If a
fresh fix is already computing, marking the old display stale does not cancel that
fresh calculation. Revision checks still prevent older results or activity
completion from overwriting newer work.

## Explicit CRS selection

Unresolved projects show **CRS required**. Users enter a numeric EPSG code or an
explicit `EPSG:<code>` identifier and choose **Validate and use EPSG**. Syntax,
backend availability and output-unit compatibility are checked with the existing
PROJ adapter. Invalid selection clears any earlier live result/confirmation.

An imported explicit EPSG remains visible and is never overwritten. Users choose
**Confirm imported CRS** before positioning. Manual selection is separately
labeled. `ConfirmedProjectCRS` tracks `landXML` versus `manual` provenance; the
original Project.crsResolution remains intact. Each new imported project resets
confirmation and location state. Nothing infers identity from filename, name,
coordinate magnitude, datum or phone location.

The UI shows EPSG, project output units, native CRS units and provenance. Linear
native units may differ from project units because the Phase 2A adapter explicitly
converts them. Degree CRS/linear project mismatch and unknown project units fail.
International and US survey feet remain distinct. No production persistence exists.

## CoreLocation and permission behavior

The app creates CLLocationManager on the main runloop. Its delegate callbacks
are handled on that actor, following [Apple's delegate threading contract](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate).
Only explicit **Start Location** requests [When In Use permission](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()).
The Info.plist purpose explains roadway station/offset relative to an imported
alignment. There is no Always request, background entitlement or location mode.

The service requests `kCLLocationAccuracyBestForNavigation`, no distance filter,
`.otherNavigation` activity, and disables automatic pausing while explicitly active.
Requested accuracy is not a guarantee. Denied, restricted, not-determined and
authorized states are distinct. Existing authorizedAlways grants are recognized
without ever requesting one. Reduced/approximate accuracy authorization is visible
and results receive a poor-accuracy warning.

**Stop Location**, leaving the Field Position screen or leaving the foreground
stops updates, removes the fix/result and invalidates outstanding work. Permission
revocation removes current results. Transient service failures are shown and later
valid updates may recover. Starting never reads CLLocationManager.location as a
current fix. Callback batches use their newest timestamp; out-of-order older fixes
cannot overwrite a newer one.

The physical-iPhone finding was stationary fixes arriving roughly every 4–6+
seconds. CLLocationManager does **not** guarantee a fixed callback frequency:
desiredAccuracy, distanceFilter and activity type influence behavior, while iOS
controls delivery cadence. Inspection found no RoadStation throttling, debounce,
sleep, polling interval or distance suppression. Every active/authorized
didUpdateLocations callback forwards its newest batch sample. Superseded results
are discarded after asynchronous work; eligible callbacks still enter calculation.
The one-second UI clock updates displayed age/classification only and never polls
the service or requests a calculation. All CoreLocation settings remain unchanged.

## Quality policy

Centralized `LocationQualityPolicy` defaults:

| Rule | Default behavior |
| --- | --- |
| maximum age | 5 seconds; older fixes cannot produce new stationing; last successful snapshot remains labeled stale/last-known |
| horizontal accuracy warning | above 10 meters: retain approximate result, warn prominently |
| future timestamp skew | more than 2 seconds ahead: reject |
| accuracy validity | negative or non-finite horizontalAccuracy: reject |
| coordinate validity | non-finite/out-of-range latitude/longitude: reject |
| cached start fix | timestamps predating Start: withhold |

Freshness is checked before and after computation, including execution/queue delay.
The foreground UI refreshes age/status every second so a formerly ready result
becomes visibly stale even when callbacks stop. Poor accuracy never permanently discards the
sample; a later fresh accurate fix recovers normally. Ambiguity takes priority in
the status while the poor-accuracy warning/measurement remains visible.

GPS accuracy is provided by CLLocation in meters and is explicitly converted
into project units for display using the existing exact unit definitions. Station,
offset and project coordinates remain in the project's declared units. Valid
speed/course are retained in sample metadata only; negative/non-finite speed and
course outside [0,360) are absent and do not affect stationing. Height is not used.

## Live result and simulator injection

Field Position shows dominant station and LT/RT/ON offset, GPS accuracy,
Easting/Northing, location age, alignment and EPSG. Blocking statuses explain
permission, missing/unconfirmed/unavailable CRS, invalid/stale location,
transformation error or stationing error. Nearest-location ambiguity is explicit
and the result is labeled representative rather than unique.

DEBUG-only fields inject WGS84 latitude/longitude and accuracy in meters. They
use the same session calculation method, PROJ transformation and AlignmentEngine
as device fixes. Only the permission/source boundary differs. The source is
conspicuously **DEBUG injected location**; the service is stopped during injection.
The synthetic fix becomes stale/last-known under the same policy. System-simulated CLLocation data
is separately labeled from device data. Injection controls/entry point are absent
in Release. There are no special expected station/offset values in production code.

## Transformer performance

The benchmark runs the existing full per-call context/database/operation lifecycle
on an Apple Silicon Mac, with 10 warmups and 200 measured forward transforms per
CRS. Geographic samples vary slightly; output uses US survey feet. Debug results:

| Destination | mean | p50 | p95 | max |
| --- | --- | --- | --- | --- |
| EPSG:3857 | 2.024 ms | 1.257 ms | 4.180 ms | 51.736 ms |
| EPSG:6507 | 5.155 ms | 4.979 ms | 6.195 ms | 6.443 ms |

At an expected roughly 1 Hz CoreLocation rate, mean cost uses about 0.2–0.52% of
one 1000 ms update interval on this Mac. At a 10 Hz burst the same mean cost would
use about 2–5.2% of a 100 ms interval; CoreLocation does not promise a fixed cadence.
Caching is not justified by this evidence.
The Phase 2A transformer stays unchanged; no global mutable PROJ state or cached
operation/session was introduced. Each successful live calculation also records
actual projection milliseconds. Physical-iPhone performance and system delivery
rates still need measurement; Mac timing is not a device timing claim.

Reproduce with:

```sh
swift run --package-path RoadStationApp/CRSAdapter roadstation-transform-benchmark
```

## Tests and validation

Root Debug and Release: **151 core + 6 harness tests pass each**.
Apple package Debug: **12 existing CRS + 27 field tests pass on macOS**.
Apple package Release: **12 CRS + 26 field tests pass**; DEBUG injection is excluded.
New cases cover permission states/request behavior/revocation/reduced accuracy,
current versus cached/stale fixes, timer expiry, poor/invalid accuracy, invalid
coordinates/timestamps, explicit confirmation/provenance, invalid/unsupported EPSG,
angular/linear/unknown units, exact accuracy conversion, transformation failure,
nearest ambiguity, alignment and CRS changes, stop/late callbacks, CoreLocation
sample conversion, configurable policy, concurrent location/CRS validation,
discarding validation after project replacement and the DEBUG injection pipeline.
The stale-timer test also verifies repeated expiry checks do not republish stale
state and restart the UI refresh loop.
Eight display/callback regressions additionally cover initial loading, snapshot preservation
and one atomic replacement publication, failure retention, out-of-order
completion/receipt, superseded activity completion, stale display while a fresh fix
is pending, threshold crossing/repeated stale checks/no calculation from stale data,
fresh replacement and all eight rapid service callbacks reaching transformation.
Test-only gates wrap the real transformer to control completion order;
production location updates contain no artificial delay.

The deterministic station test uses [NGA's independently published EPSG:3857 point](https://github.com/ngageoint/projections-ios/blob/3.0.0/proj-iosTests-swift/PROJSwiftReadmeTest.swift)
at 1°E,1°N and a synthetic line around that fixed point. Expected E/N,
station 43+96.42 and offset 5 m LT do not come from a RoadStation inverse.
The UI injection case derives geographic input with the independent spherical
Mercator inverse formula for 1050E/1995N US survey feet, then uses the actual app
pipeline to check 100+50.00, 5 ft RT and displayed accuracy.

Reproduction commands (use an installed iPhone Simulator name/OS):

```sh
swift test
swift test -c release
swift test --package-path RoadStationApp/CRSAdapter
swift test --package-path RoadStationApp/CRSAdapter -c release
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj \
  -scheme RoadStationCRSTests -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
tools/Test-iOS-Harness.sh YOUR_SIMULATOR_UDID
swift run roadstation-validate \
  Validation/RealORD/CROSSGATES/CROSSGATES.xml \
  Validation/RealORD/CROSSGATES/CROSSGATES-ord-cases.json \
  validation-output/CROSSGATES
```

Simulator verification used **iPhone 18 Pro, iOS 27.0, Xcode 27.0**:

| Check | Final result |
| --- | --- |
| RoadStationApp Debug simulator build | succeeded |
| RoadStationCRSTests (CRS + field-position) | 39/39 passed for the retention fix; Phase 2B.1 expands this to 53/53 |
| complete existing harness UI suite plus Phase 2B case | 6/6 passed |
| explicit EPSG/injected-position UI | 100+50.00, 5.0 ft RT, ±13.1 ft, E1050/N1995; DEBUG source visible |

The UI case also confirms stable result-card height/position through fresh → stale/last-known → fresh, invalid EPSG handling, Start disabled before
confirmation, and Stop clearing the station. Existing manual/canvas, station
equation, spiral, multiple-alignment and Files import/error assertions pass.
Files-import tests now scroll to the alignment row because the new CRS controls
increase page height. A stale-state refresh loop found in the first UI run was
fixed and is covered by the deterministic repeated-refresh regression.

The continuous-display fix was verified by rerunning root Debug/Release, macOS
Debug/Release, the iOS suite, simulator build, all six UI tests and CROSSGATES.
The analytic CLI cases also pass 2/2 with zero error. Current logs are under
ignored `validation-output/phase2b-display-fix/`: `core-debug.log`,
`core-release.log`, `apple-debug.log`, `apple-release.log`, `ios-crs-tests.log`,
`app-build.log`, `ui-tests.log`, `ord-validation.log` and `analytic-validation.log`.
Current result bundles are `validation-output/phase2b-display-fix/CRS.xcresult`
and `validation-output/phase15/UI-20261003-202120.xcresult`. The earlier integration
evidence and unchanged-transformer benchmark are retained in
`validation-output/phase2b/`.

CI's macOS Apple-package command automatically includes the new field suite.
The iOS RoadStationCRSTests target includes the same new source, so its existing
portable simulator Actions step runs both CRS and field tests. CI additionally
runs the bundled-sample explicit CRS/injected field-position UI test, and CROSSGATES
with its original case file and tolerances on the root matrix. The complete Files
picker UI suite remains a local harness-script check because it needs staged files.

### CROSSGATES regression

**30/30 passed; 0 failed**, unchanged **0.001 US survey foot** tolerances.
Lines 6/6, curves 8/8, spirals 10/10, station equations 6/6.
Maximum station error: 0.0004701052457676269 US survey foot.
Maximum offset error: 1.0457828953754054e-7 US survey foot.
Maximum coordinate error: 0.0004701052042923065 US survey foot.
No core geometry, alignment parser, ORD inputs or tolerance definitions changed.

## Physical-device status and limitations

Earlier iPhone installation/launch verification does not validate Phase 2B field
behavior. Physical iPhone permission UX, Precise Location behavior, battery use,
update cadence, speed/course, timing, known-point positions and station/offset
accuracy **still need testing**. The user subsequently reported physical-iPhone stationary fixes around 4–6+ seconds, exposing the stale-card collapse; the corrected stale/last-known retention still needs physical-device verification.

No MapKit, background location, camera/photos, cloud sync or production persistence.
Phone GPS is approximate and not survey-grade. Poor fixes may have large offsets
and are intentionally shown only with warning. This phase does not enforce an
alignment-distance or longitudinal-residual safety gate. EPSG operation accuracy,
missing-grid availability, datum/epoch and CRS-area limitations from Phase 2A
still apply. CRS confirmation is a user assertion, not proof that the imported
geometry uses that CRS. The 5-second/10-meter defaults require field review.

## Phase 2B.1 follow-up

The dedicated searchable/recommended CRS picker is now implemented in the same
working branch. See [PHASE2B1_CRS_PICKER_REPORT.md](PHASE2B1_CRS_PICKER_REPORT.md)
for the final combined 53/52 Apple Debug/Release tests, iOS, UI and validation
evidence. It replaces primary manual numeric entry while preserving advanced
EPSG selection, live-position calculations and the stale/last-known fix.

## Exact Phase 2C recommendation

Make Phase 2C a controlled physical-iPhone validation and field-safety gate before
adding any map: collect known-point traces against independently surveyed/ORD
references in confirmed project CRS/units; record raw WGS84 fixes, timestamps,
accuracy, permission precision, projection cost, E/N and station/offset. Add visible
operation accuracy/grid/area/provenance disclosure and configurable alignment-
distance/longitudinal-residual thresholds. Validate permission changes, foreground
transitions and denied/reduced-accuracy recovery on device. Retain all 30 CROSSGATES
cases and the deterministic suites. Revisit transformer caching only if measured
phone update cost warrants it. MapKit can follow as a display layer after this gate.
