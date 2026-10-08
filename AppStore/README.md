# RoadStation 1.0 paid release

Launch choices: individual seller using the legal name verified during Apple enrollment, English, United States, US$4.99 paid download, Productivity / Utilities, standard Apple license, manual release. No StoreKit integration is needed for a paid download. Public URLs are https://vericivil.com/roadstation, /roadstation/privacy, /roadstation/support and /roadstation/sample.landxml. Support: support@vericivil.com (forwarding and incoming/reply round-trip verified October 7, 2026).

## Release sequence

1. Enroll as an individual at https://developer.apple.com/programs/enroll/; complete identity verification yourself. Activate the Paid Apps Agreement and enter tax/bank information directly in App Store Connect. Register com.colewinstead.RoadStationApp and create its record. Select the enrolled Xcode team and automatic distribution signing.
2. Set US-only availability and $4.99 USD base price, categories above, English metadata, standard EULA and manual release. Complete age-rating and content-rights questionnaires truthfully; this is an engineering utility without user content, advertising, messaging or accounts. Check current questions rather than guessing a final rating.
3. Run the validation below, device checks, archive inspection and Organizer privacy report. Increment CURRENT_PROJECT_VERSION for every upload; MARKETING_VERSION remains 1.0. Retain exact commit, archive, reports and screenshots with each build.
4. Validate/upload through Xcode Organizer. Wait for processing and resolve privacy/export errors. Pilot through TestFlight, fix crashes/data loss/misleading positions, then submit the tested build with reviewer notes. Release manually only after review approval and every required gate passes.
5. Add the verified App Store URL to VeriCivil after it exists. Monitor App Store Connect crashes and the support inbox.

## Repeatable validation

```sh
swift test
swift test -c release
swift test --package-path RoadStationApp/CRSAdapter
swift test --package-path RoadStationApp/CRSAdapter -c release
python3 tools/Generate-CRS-Catalog.py --check
swift run roadstation-validate Validation/RealORD/CROSSGATES/CROSSGATES.xml Validation/RealORD/CROSSGATES/CROSSGATES-ord-cases.json validation-output/CROSSGATES
swift run roadstation-validate AppStore/sample.landxml AppStore/sample-cases.json validation-output/app-store/sample
tools/Test-iOS-Harness.sh SIMULATOR_UDID Debug
tools/Test-iOS-Harness.sh SIMULATOR_UDID Release
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj -scheme RoadStationApp -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/RoadStation-Release CODE_SIGNING_ALLOWED=NO build
python3 tools/Check-Release-App.py /tmp/RoadStation-Release/Build/Products/Release-iphoneos/RoadStationApp.app
```

The Release smoke uses the actual Files picker, confirms EPSG:6507, checks the public sample manual result, reopens the saved project and checks Help/About and absence of developer controls. It deletes only its own uniquely named project. This does not prove physical GPS accuracy. Screenshots from its xcresult attachments are candidate assets; review/crop only to Apple requirements, never fabricate GPS or change numerical results.

## Required device gates (pending until recorded)

- Physical iPhone: precise, approximate and denied permission; stale fixes; background/re-entry; offline Engineering View; source replacement; saved-project recovery. Record device/iOS/build, steps and observed outcome.
- Known point: document EPSG, datum, axis order, units/foot type, control provenance and actual coordinates. Separate engine numerical error from observed phone-location error; do not adjust geometry to imagery.
- iOS 17 and current iOS; small display; landscape; large text; VoiceOver. Record unavailable hardware/runtime checks as pending.
- Signed archive, Organizer validation/upload/processing, complete archive privacy report, TestFlight pilot, review approval, support email round-trip and final listing screenshots.

## Listing draft

**Name:** RoadStation

**Subtitle:** LandXML station and offset

**Keywords:** LandXML,station,offset,roadway,alignment,civil,engineering,inspection,CRS

**Description:** Bring supported LandXML roadway alignments to your iPhone. Import from Files, confirm the project coordinate system and units, and select an alignment. Read horizontal station and left/right offset from approximate phone positioning, inspect coordinates manually, or query station and offset. Keep projects on your device for return visits. Geographic maps provide context; Engineering View displays the local alignment when map imagery is unavailable. Check positioning accuracy and stale-fix warnings before interpreting results. Phone GPS is approximate, not survey-grade positioning. Confirm project control, CRS and exact units before field use. No app accounts, subscriptions or cloud sync. Requires iOS 17 or later.

**Copyright:** 2026 Cole Winstead

**Support URL:** https://vericivil.com/roadstation/support

**Privacy URL:** https://vericivil.com/roadstation/privacy

**Reviewer notes:** No login required. Download https://vericivil.com/roadstation/sample.landxml to Files. Import LandXML, confirm EPSG:6507 and US survey feet, select Example alignment, open Inspect Alignment → Entry. X=986377.5959036754, Y=1453406.9250950934 produces STA 100+50.00, 5.000 ft RT. Inverse station=10050 and offset=-5 returns the same coordinates. The sample is fictional geometry, not survey control. Reviewers away from it can test import, CRS, maps, manual queries and saved-project reopening; live GPS uses the real phone position. Help & About is on Projects. Supply the seller's reachable review phone/email directly in App Store Connect.

## Public sample provenance

sample.landxml is derived from the existing synthetic EPSG:6507 sr82_synthetic.xml reference fixture. Names identify it as fictional; the unused empty CgPoints container is omitted. sample-cases.json contains two analytically derived first-tangent checks at unchanged 1e-6 source-unit tolerance. It contains no private validation data. CROSSGATES remains a separate numerical reference validation and is never shipped.
