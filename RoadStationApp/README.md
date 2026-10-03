# RoadStationApp — Phase 1.5 developer harness

A session-only SwiftUI iPhone harness for the authoritative RoadStationCore
package. It provides manual horizontal geometry inspection before real ORD
numerical comparison. **Independent ORD validation is pending. Phase 2 GPS/CRS
functionality remains blocked.** No expected ORD results are bundled.

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
RoadStation/Core/                   authoritative engine (not copied or edited)
RoadStationApp/
  RoadStationApp.xcodeproj/          app, UI-test target and shared scheme
  RoadStationApp/                    SwiftUI screens, models and Info.plist
  HarnessSupport/                   planar viewport and input parsing only
  HarnessSupportTests/              platform-independent helper tests
  RoadStationAppUITests/             actual simulator UI flows
```

The Xcode app target links **RoadStationCore** and **RoadStationHarnessSupport**
via the repository's local Swift package. The helper product contains only UI
coordinate conversion and text adapters. Existing core source/test targets are
unchanged. Sample resource references point directly to five checked-in fixture
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
Existing core suite: **142 tests**. New helper suite: **6 tests**. See the root
`PHASE15_REPORT.md` for actual simulator/build/UI outcomes and screenshot evidence.
UI import tests need the staged files; run the script before running them in Xcode.

The user has confirmed successful physical iPhone installation and app launch
using Xcode automatic signing with a Personal Team. This verification covers
installation and launch only; it does not establish GPS, MapKit, CRS, or
field-location validation.

| Capability | Status |
| --- | --- |
| Physical iPhone app installation/launch | **VERIFIED** — user-confirmed, Xcode automatic signing with a Personal Team |
| Production/App Store distribution | **NOT VERIFIED** |
| CoreLocation/GPS field behavior | **NOT IMPLEMENTED / NOT VERIFIED** |
| MapKit/geographic maps | **NOT IMPLEMENTED / NOT VERIFIED** |
| CRS transformations | **NOT IMPLEMENTED** |
| Independent ORD numerical validation | **STILL PENDING** |

## Intentional limits

Developer harness only: no geographic map, CRS transformation, CoreLocation,
GPS/GNSS, camera, photos, reports, account, database or cloud service. Drawing
accuracy uses the core's fixed 0.05 source-unit chord-error sampling; deeper zoom
magnifies its display approximation, while calculations remain independent.
Pan/pinch zoom is centered on the viewport rather than the pinch location.
Import/parser warnings are visible, and unsupported geometry is rejected by the
core. Large complex XML/spirals can still reach existing parser/numerical limits.
No process/session persistence or multi-project management is provided. Physical
iPhone installation/launch is verified; broader on-device workflow or
field-location validation is not claimed. Production/App Store distribution is
**NOT VERIFIED**; release packaging and App Store readiness are outside this phase.

The next engineering gate is independent ORD numerical comparison, including
real clothoids and station equations. This harness does not satisfy that gate.
