# RoadStationApp — Phase 2B.1 developer harness

A session-only SwiftUI iPhone harness for the authoritative RoadStationCore
package. It provides manual horizontal geometry inspection and CRS readiness
after import. **CROSSGATES ORD validation passed 30/30 cases at 0.001 US survey
foot tolerance.** CRS architecture and transformation tests are implemented;
foreground live location and explicit searchable CRS selection are implemented.
MapKit and production persistence remain unimplemented. Field-device testing is
still needed. See [PHASE2B_LOCATION_REPORT.md](../PHASE2B_LOCATION_REPORT.md). See
[PHASE2_CRS_REPORT.md](../PHASE2_CRS_REPORT.md). No expected ORD results are bundled.

## Open and run in Xcode

1. Open `RoadStationApp/RoadStationApp.xcodeproj` from the repository root.
   Keep the project inside this repository: its local package reference is `..`.
2. Select the shared **RoadStationApp** scheme and an available **iPhone Simulator**
   or connected physical iPhone.
   This harness targets iOS **17.0 or later**, and was built with Xcode 27.0.
3. Choose Product > Run (⌘R). Simulator builds do not require a paid developer
   account. Physical iPhone installation and app launch are verified using Xcode
   automatic signing with a Personal Team, as reported by the user.
4. Select **Import LandXML** or a **Synthetic developer sample** in the Debug build.
   Tap an alignment row to open the workspace. Use Inspect, Entry, Info and Raw.

To build from a terminal (substitute your simulator UDID):

```sh
xcrun simctl list devices available
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj \
  -scheme RoadStationApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath /tmp/RoadStationApp-DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot YOUR_SIMULATOR_UDID
xcrun simctl bootstatus YOUR_SIMULATOR_UDID -b
xcrun simctl install YOUR_SIMULATOR_UDID \
  /tmp/RoadStationApp-DerivedData/Build/Products/Debug-iphonesimulator/RoadStationApp.app
xcrun simctl launch YOUR_SIMULATOR_UDID com.colewinstead.RoadStationApp
```

Skip `boot` if the device is already booted. Use Debug to expose synthetic samples.
The Release configuration retains import/manual tools but hides sample controls.

## Import from Files

The app uses SwiftUI `fileImporter` for `.xml` and `.landxml`. Reads are bracketed
by security-scoped URL access where granted, following
[Apple's fileImporter requirements](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)).
Parsing occurs off the main actor. Errors appear on the import screen; an existing
session project remains available if a replacement fails. No import is saved.

On a physical iPhone, put the XML in Files (On My iPhone or another document
provider) and pick it. For Simulator you can copy a file into the app's shared
Documents folder after installation:

```sh
app_data_dir="$(xcrun simctl get_app_container YOUR_SIMULATOR_UDID com.colewinstead.RoadStationApp data)"
mkdir -p "$app_data_dir/Documents"
cp Tests/Fixtures/tangent-only.xml "$app_data_dir/Documents/example.xml"
```

In **Import LandXML**, choose Browse > On My iPhone > RoadStation > example.
`UIFileSharingEnabled` and opening documents in place expose this folder for
manual test inputs. The harness does not persist imported models/bookmarks,
query histories, or project state. The test script stages only synthetic input
files in that simulator folder so the actual picker flow can be exercised.

## Screens and operations

- **Project/import:** project name, unconverted units, CRS description if present,
  project warnings, alignment count and rows with start station/length/segments.
- **Engineering canvas:** north-up planar centerline with aspect-preserving fit,
  drag pan, pinch/button zoom and Fit. Subtracts the local coordinate origin for
  display, retaining the full engineering values in the core. Line is primary
  color, arc blue, spiral purple. Sampling is exclusively for drawing.
- **Inspect:** tap converted to Easting/Northing; station, signed offset/side,
  query/nearest coordinates, segment index/type and bearing. Query marker is
  orange, nearest marker blue, with a connector. Ambiguity is prominent in red.
- **Entry:** coordinate → station/offset and station/offset → coordinate forms.
  StationFormatter handles `427+38.42` or numeric station. LT positive, RT
  negative, ON zero; enter a nonnegative magnitude. Ambiguous station equations
  show candidates and require an explicit zero-based branch choice. Manual
  results are fitted to the canvas. Inverse coordinates and branch metadata are
  shown separately from a forward check of the plotted point.
- **Info:** units, geometry-type counts, warnings, metadata, cumulative segment
  distances and station equations/back/ahead labels.
- **Raw:** query, geometric distance, numeric/formatted station, signed offset,
  side, tangent, bearing in radians, nearest coordinate, query distance,
  longitudinal residual and ambiguity. Numeric values retain 9–12 decimals here.

All calculations call `AlignmentEngine` / `StationingEngine`; sampled paths never
supply calculated answers. A forward check may legitimately differ from an
inverse request outside a unique normal neighborhood. If that optional forward
check fails, the valid inverse coordinate remains displayed and plotted.

## Package/project structure

```text
Package.swift                       unchanged core product + harness helper product
RoadStation/Core/                   authoritative geometry + portable CRS model
RoadStationApp/
  RoadStationApp.xcodeproj/          app, UI/CRS test targets and shared schemes
  RoadStationApp/                    SwiftUI screens, models and Info.plist
  HarnessSupport/                   planar viewport and input parsing only
  HarnessSupportTests/              platform-independent helper tests
  RoadStationAppUITests/             actual simulator UI flows
  CRSAdapter/                       NGA PROJ adapter and shared macOS/iOS CRS tests
```

The Xcode app target links **RoadStationCore**, **RoadStationHarnessSupport**,
**RoadStationAppleCRS**, **RoadStationCRSCatalog**, **RoadStationFieldPosition** and the installed **Projections** product. The core package
remains independent of projection libraries and Apple location/map frameworks.
The harness helper contains only viewport and manual-input adapters. Phase 2A
adds CRS models/import identification without editing validated geometry. Sample resource references point directly to five checked-in fixture
files; these sources are not duplicated in the repository. Debug sample controls
explicitly identify every sample as synthetic, including projected SR 82.

## Verification

```sh
swift test
swift test -c release
tools/Test-iOS-Harness.sh YOUR_SIMULATOR_UDID
```

The script builds/installs the app, stages synthetic `.xml`/`.landxml` and malformed
inputs in Simulator Files, and runs the shared scheme's UI tests without parallel
simulator cloning. Results go under ignored `validation-output/phase15/`.
Core suite: **151 tests** (142 existing + 9 CRS). Helper suite: **6 tests**.
Apple CRS adapter suite: **12 tests**. Phase 2B/2B.1 field-position/picker suite: **33 Debug
tests** (32 Release; the injection entry point is Debug only), shared by macOS and
iOS Simulator. The catalog adds **8 tests**. See `PHASE2B1_CRS_PICKER_REPORT.md` in the repository root for current
simulator/build/UI outcomes and `PHASE15_REPORT.md` for the earlier harness evidence.
UI import tests need the staged files; run the script before running them in Xcode.

The user has confirmed successful physical iPhone installation and app launch
using Xcode automatic signing with a Personal Team. This verification covers
installation and launch only; it does not establish GPS, MapKit, CRS, or
field-location validation.

| Capability | Status |
| --- | --- |
| Physical iPhone app installation/launch | **VERIFIED** — user-confirmed, Xcode automatic signing with a Personal Team |
| Production/App Store distribution | **NOT VERIFIED** |
| CoreLocation/GPS field behavior | **IMPLEMENTED** — physical-device field validation still needed |
| MapKit/geographic maps | **NOT IMPLEMENTED / NOT VERIFIED** |
| CRS transformations | **IMPLEMENTED** — explicit confirmation + live-location pipeline |
| Independent ORD numerical validation | **PASSED 30/30** — CROSSGATES, 0.001 US survey foot |

## Intentional limits

Developer harness only: no geographic map, background location, camera, photos,
reports, account, production persistence or cloud service. Drawing
accuracy uses the core's fixed 0.05 source-unit chord-error sampling; deeper zoom
magnifies its display approximation, while calculations remain independent.
Pan/pinch zoom is centered on the viewport rather than the pinch location.
Import/parser warnings are visible, and unsupported geometry is rejected by the
core. Large complex XML/spirals can still reach existing parser/numerical limits.
No process/session persistence or multi-project management is provided. Physical
iPhone installation/launch is verified; broader on-device workflow or
field-location validation is not claimed. Production/App Store distribution is
**NOT VERIFIED**; release packaging and App Store readiness are outside this phase.

The next Phase 2C step is controlled physical-iPhone known-point validation,
operation provenance and field-safety gates. Phase 2B does not establish survey
accuracy. The CRS adapter is independently testable:

```sh
swift test --package-path RoadStationApp/CRSAdapter
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj \
  -scheme RoadStationCRSTests \
  -destination "platform=iOS Simulator,id=YOUR_SIMULATOR_UDID" test
```


## Phase 2B Field Position

Import a project and confirm its explicit LandXML EPSG, or open **Choose Coordinate
System**, browse/search and explicitly choose **Use CRS**. Advanced **Enter EPSG
manually** still offers **Validate and use EPSG**. The original imported identity remains visible; manual
selection is labeled separately. Output is converted to the declared project
unit using the existing adapter. Unknown units/geographic degrees cannot be used
for planar stationing. Selection is session-only and never guessed.

Open an alignment, then **Live Location / Field Position**. **Start Location**
requests When In Use permission if needed. **Stop Location**, leaving this screen,
or leaving the foreground stops updates. Denied/restricted permission and
approximate-location status remain visible. Station/offset are dominant, with
GPS accuracy, Easting/Northing, fix age, alignment and EPSG context.

Default policy: fixes become ineligible for new calculation after 5 seconds; accuracy greater than 10 meters
shows a poor-accuracy warning with the approximate result retained. Cached fixes
predating Start are withheld. Invalid coordinates/accuracy/timestamps are
excluded from new calculation. Ambiguous nearest results remain explicitly marked.

After the first successful fix, its station/offset and matching accuracy/timestamp
remain visible while the next fix computes. The completed position replaces all
displayed values together; the small update indicator does not change card size.
If it becomes stale, the snapshot stays visible with **Stale — last known position**
and its current age. A fresh successful fix replaces it and removes that warning.
Repeated stale checks do not erase or republish it. Invalid/failed subsequent updates
also retain the last-known snapshot with a warning. Stop, project/alignment/CRS
replacement and permission revocation clear it. The five-second safety classification
is unchanged; stale data never produces a new station/offset calculation.

RoadStation does not throttle/debounce or poll CoreLocation. Every active authorized
callback is processed; iOS controls its cadence and does not promise periodic fixes.
Best-for-navigation accuracy, no distance filter and automatic pausing disabled
remain unchanged. The one-second UI clock only updates age/classification.

Debug builds provide **DEBUG location injection**: enter WGS84 degrees and
horizontal accuracy in meters. The real projection/geometry pipeline is used,
with a conspicuous injection label and the same freshness policy. No injected
control exists in Release. No physical-device field-accuracy claim is made.

```sh
swift run --package-path RoadStationApp/CRSAdapter roadstation-transform-benchmark
```

## Phase 2B.1 CRS picker

Choose Coordinate System opens a dedicated Recommended / Browse / Search sheet.
Browse includes 1,081 State Plane EPSG definitions across all 50 states and Puerto
Rico/Virgin Islands jurisdictions. Search names, state/zone, datum, unit or EPSG
code; for example Mississippi West, NAD83 2011, survey foot or 6510. A preview
shows project/native units and requires **Use CRS**. Imported LandXML EPSG remains
prominent with imported confirmation provenance. Advanced manual EPSG entry is
still available inside the sheet.

**Choose CRS** requests a fresh one-time location when already authorized. With
undetermined permission, **Use My Location** requests When In Use permission,
then one fix. Denied/restricted permission leaves Browse, Search and manual entry
available. A separate manager uses `requestLocation()` only: it never starts
continuous updates or Field Position, calculates stationing, or selects a CRS.
The acquired fix is checked once, then its recommendations stay available for the
sheet with capture time and accuracy in project units. Poor/reduced accuracy
shows an approximate warning. Finding/refresh status preserves the layout and
prior capture; failure offers explicit retry. The live five-second stale policy
is unchanged. Published rectangular areas are not precise zone polygons.

The Apple catalog is generated from the pinned NGA proj.db, cached as immutable
Swift metadata and searched off MainActor. It distinguishes US survey feet,
international feet and meters, and labels different convertible native units.
DEBUG fix injects a clearly synthetic recommendation position through shared
acquisition/ranking logic; it retains the capture for the picker presentation. See the Phase 2B.1
report for membership rules, compiled C APIs, performance and full validation.

```sh
python3 tools/Generate-CRS-Catalog.py --check
swift test --package-path RoadStationApp/CRSAdapter -c release
```
