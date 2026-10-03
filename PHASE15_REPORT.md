# Phase 1.5 — RoadStationApp developer harness

RoadStationApp is a native SwiftUI harness for manual inspection of the frozen
Phase 1 engine. Independent ORD numerical validation remains pending and is
still the gate before Phase 2. No production GPS/CRS functionality was added.

## Repository state and core preservation

The Phase 1 audit PR #1 was already merged when this work began. Its audit commit
`8f1cafe8982a55f0419fdf7d2d64abe092c0e270` is preserved in main's merge
`e3b492d`. This work starts from that main on `codex/phase15-ios-harness`.
`RoadStation/Core/`, `RoadStation/CLI/` and every existing file in `Tests/` are
unchanged. No existing test, tolerance, geometry convention or expected result
was weakened or replaced.

## Files added and modified

Added:

- `RoadStationApp/RoadStationApp.xcodeproj/project.pbxproj`
- `RoadStationApp/RoadStationApp.xcodeproj/xcshareddata/xcschemes/RoadStationApp.xcscheme`
- `RoadStationApp/RoadStationApp/RoadStationApp.swift`
- `RoadStationApp/RoadStationApp/HarnessModels.swift`
- `RoadStationApp/RoadStationApp/ProjectView.swift`
- `RoadStationApp/RoadStationApp/AlignmentWorkspace.swift`
- `RoadStationApp/RoadStationApp/EntryTools.swift`
- `RoadStationApp/RoadStationApp/EngineeringCanvas.swift`
- `RoadStationApp/RoadStationApp/InspectionViews.swift`
- `RoadStationApp/RoadStationApp/Info.plist`
- `RoadStationApp/HarnessSupport/CanvasViewport.swift`
- `RoadStationApp/HarnessSupport/ManualQuery.swift`
- `RoadStationApp/HarnessSupportTests/HarnessSupportTests.swift`
- `RoadStationApp/RoadStationAppUITests/RoadStationAppUITests.swift`
- `RoadStationApp/README.md`
- `tools/Test-iOS-Harness.sh`
- `PHASE15_REPORT.md`

Modified: `Package.swift` adds only the harness helper product/target and its test
target; root `README.md` links the harness; `.github/workflows/core-tests.yml`
adds an iPhone Simulator build while retaining the macOS/Ubuntu package matrix.
Runtime screenshots, logs and result bundles live under ignored
`validation-output/phase15/`, not in the application bundle or git source.

## Xcode project and engine link

```text
Road-Stationing-App/
  Package.swift
  RoadStation/Core/                 RoadStationCore source of truth
  RoadStation/CLI/                  existing independent validation CLI
  Tests/                           unchanged 142 core tests and fixtures
  RoadStationApp/
    RoadStationApp.xcodeproj/       shared RoadStationApp scheme
    RoadStationApp/                 SwiftUI application target
    HarnessSupport/                viewport and text adapters
    HarnessSupportTests/           six package tests
    RoadStationAppUITests/          simulator interaction tests
```

The app target depends on the repository-local Swift Package reference `..`,
linking `RoadStationCore` and `RoadStationHarnessSupport`. Core sources are not
copied into the Xcode target. There are no third-party UI packages. Deployment
target is **iOS 17.0**, matching the existing package minimum. Swift language mode
is 6. The app is configured for iPhone. Physical iPhone installation and app
launch are verified using Xcode automatic signing with a Personal Team, as
reported by the user. iPad operation has not been verified.

## Screens and behavior

1. **Project/import:** native Files picker accepts `.xml` and `.landxml`.
   Security-scoped access encloses the read/parse operation and is balanced when
   granted. `LandXMLParser` runs off the main actor. Errors are visible; a failed
   replacement retains the prior session project. Summary includes project name,
   units, source, coordinate-system description, count and warnings. Each
   selectable alignment row lists name, start station, length and segment count.
2. **Engineering workspace:** north-up planar canvas supports aspect-preserving
   fit, drag pan, pinch and zoom buttons. The display subtracts a local origin
   before scaling so large projected coordinates retain precision. Lines, arcs
   and spirals use separate display paths/colors; gaps are not joined.
   `AlignmentSampling` supplies drawing only. Taps transform back to full
   engineering coordinates and call `AlignmentEngine.stationOffset(point:)`.
   Query/nearest markers and offset connector accompany station, offset, side,
   query/nearest E/N, segment type/index and bearing. Core ambiguity is explicit
   and red; results are never silently treated as unique.
3. **Entry:** E/N → station/offset and station/offset → E/N forms use finite
   decimal input and `StationFormatter`. Positive LT, negative RT, ON zero.
   Offset input is a nonnegative magnitude. Inverse results show E/N, geometric
   distance, segment index and equation branch, then plot the result. Station
   overlap requires an explicit branch selection; the UI supplies no default.
   An optional forward inspection cannot discard a valid inverse coordinate.
4. **Info:** metadata, project units, line/curve/spiral counts, warnings,
   geometric segment start/end distances and station-equation back/ahead labels.
5. **Raw:** developer comparison values include raw/formatted station, signed
   offset/side, geometric distance, segment type/index, tangent, bearing,
   longitudinal residual, query/nearest coordinates and ambiguity. No fake ORD
   values are supplied. Indices are explicitly zero-based.

Debug sample controls point directly to five existing synthetic fixtures,
including spiral/curve/spiral, multiple alignments, station equations and SR 82
large projected coordinates. Controls are hidden in Release. Every sample is
labelled synthetic. Import/project state and queries remain session-only.

## Verified environment and results

- macOS **27.0.1 (26A434)**, Apple Silicon arm64.
- Xcode **27.0 (27A266a)**; Apple Swift **6.4**.
- Developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Actual simulator: **iPhone 18 Pro, iOS 27.0, arm64**.
- Simulator UDID: `7A82DB49-90F0-4BBF-8978-8CC72F9988F1`.
- `swift test`: **142 original core tests + 6 new helper tests passed**.
- `swift test -c release`: **142 original core tests + 6 new helper tests passed**.
- Debug iPhone Simulator `xcodebuild`: **BUILD SUCCEEDED**.
- Release iPhone Simulator `xcodebuild`: **BUILD SUCCEEDED**.
- App installation and `simctl launch`: **actually verified**, followed by
  screenshot capture and XCTest UI interaction on the booted simulator.

The user has also confirmed successful installation and launch on a physical
iPhone using Xcode automatic signing with a Personal Team. This verification
covers installation and app launch only; it does not establish GPS, MapKit, CRS,
or field-location validation.

| Capability | Status |
| --- | --- |
| Physical iPhone app installation/launch | **VERIFIED** — user-confirmed, Xcode automatic signing with a Personal Team |
| Production/App Store distribution | **NOT VERIFIED** |
| CoreLocation/GPS field behavior | **NOT IMPLEMENTED / NOT VERIFIED** |
| MapKit/geographic maps | **NOT IMPLEMENTED / NOT VERIFIED** |
| CRS transformations | **NOT IMPLEMENTED** |
| Independent ORD numerical validation | **STILL PENDING** |

The helper tests cover large-coordinate transform roundtrips with pan/zoom,
north-up isotropic scale, horizontal/vertical/degenerate bounds, finite input,
station/offset sign conventions and explicit equation ambiguity.

The final full simulator UI suite passed: **5 tests, 0 failures, 0 skipped**
(231.682 seconds; `TEST SUCCEEDED`). It covers canvas pan/pinch/fit and exact
forward/inverse input; real Files import of both extensions plus malformed XML;
second-alignment selection; explicit equation branch selection; and spiral
metadata/large-coordinate drawing. The result bundle is
`validation-output/phase15/UI-Final.xcresult`, with log
`validation-output/phase15/logs/ios-ui-final.log`.

Earlier UI iterations exposed asynchronous picker loading, remembered Files
navigation, scroll selectors and a shared focus binding. The final picker test
uses actual folder cells/back navigation, and the form uses a distinct focused
field. Canvas drag gestures keep pan within the canvas. All five cases passed in
one final run; no original core test or numerical threshold changed.

GitHub Actions verified the package debug/release tests and validation CLI on
macOS 14 and Ubuntu 24.04, plus the new macOS 15 iOS Simulator build. The app/core
implementation was verified in [run 37103003943](https://github.com/colewinstead/Road-Stationing-App/actions/runs/37103003943),
with the final UI-test navigation adjustment verified locally as described above.

Screenshots from actual simulator execution are in
`validation-output/phase15/screenshots/`:

- `project-start.png`: initial project/import screen.
- `imported-landxml-project.png`: actual .landxml import and selectable row.
- `import-error.png`: malformed XML error with prior project retained.
- `tap-inspection.png`: query and nearest markers, connector and result.
- `manual-entry.png`: E/N form and plotted calculated point.
- `equation-branch-choice.png`: ambiguity message and branch candidates.
- `spiral-workspace.png`: synthetic spiral/curve/spiral metadata.
- `projected-coordinate-workspace.png`: synthetic SR 82 large coordinates.

Package/build logs are in `validation-output/phase15/logs/`. Screenshot inputs
are synthetic; none are evidence of independent ORD validation.

## Run it yourself

1. Open `RoadStationApp/RoadStationApp.xcodeproj` in Xcode. Keep the project in
   this checkout so its relative package reference resolves.
2. Select the **RoadStationApp** shared scheme.
3. Select an installed iPhone Simulator running iOS 17.0 or newer, or a connected
   physical iPhone. The verified simulator destination was **iPhone 18 Pro
   (iOS 27.0)**. Physical iPhone installation/launch was separately verified using
   Xcode automatic signing with a Personal Team.
4. Use **Product > Run (⌘R)**, with Debug configuration for sample controls.
5. Load **Tangent • synthetic** and tap **TANGENT**, then tap near the line.
6. Select **Entry**. E `1050`, N `1995` produces `STA 100+50.00`, `5 ft RT`.
   Station `100+75.00`, magnitude `5`, LT produces E `1075`, N `2005`.
7. Load the station-equation sample. Station `103+50` requires a branch; select
   the intended candidate before calculating.
8. To test Files, install/run the app first, copy an XML into its Documents
   folder (see `RoadStationApp/README.md`), then choose **Import LandXML > Browse
   > On My iPhone > RoadStation**. A real file from any supported provider can
   also be selected. The app retains no imported model after termination.
9. Run `tools/Test-iOS-Harness.sh YOUR_SIMULATOR_UDID` for the automated UI flows.
   It stages synthetic import inputs, including both extensions and malformed
   XML. These staged Files inputs remain in Simulator Documents for manual use.

## UI limitations and future gate

The drawing uses fixed core sampling (0.05 source-unit chord error), so deep zoom
magnifies the display approximation; calculations stay independent of drawing.
Zoom is centered on the viewport, not the pinch location. The grid is visual,
not a labelled surveying grid. Long values/metadata require scrolling; the
canvas has a fixed 300-point height and is a debugging aid. Physical iPhone
installation/launch is verified; broader on-device workflow or field-location
validation is not claimed. Production/App Store distribution is **NOT VERIFIED**;
App Store assets, release distribution and large-file performance certification
are outside this phase. The managed environment supports headless simulator
execution/capture, but does not contain the normal Simulator desktop app. Its
iOS 27 automation occasionally stalls or cannot obtain an accessibility window;
failed initial attempts are not counted as successful tests. The final complete
five-test run passed after the picker test handled remembered navigation. Keyboard presentation
also emitted a SwiftUI frame-dimension runtime warning; input calculations and
UI assertions passed, but this warning has not been independently resolved.

CoreLocation, MapKit, GPS/GNSS, geographic maps, latitude/longitude, State Plane or
EPSG transformations, PROJ, camera/photos, reports, accounts, persistence,
cloud sync, subscriptions, analytics, pay items and AI features are unimplemented.
The harness does not alter CRS/unit declarations or infer missing coordinate
metadata. **Independent ORD numerical validation, including real spirals and
station equations, remains the gate before Phase 2.**
