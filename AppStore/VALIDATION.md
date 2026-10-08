# Release preparation evidence — October 7, 2026

Source branch: codex/app-store-release. Marketing version 1.0, build 1. Update this record with the exact final source commit before distribution.

## Passed

- Core Debug and Release: 151 XCTest cases per configuration, plus Swift Testing smoke checks (see logs).
- Apple packages Debug and Release: 21 CRS, 53 field/catalog, 8 map-overlay and 13 saved-project tests per configuration, zero failures.
- CRS catalog matches the pinned database.
- Independent CROSSGATES ORD: 30/30 (line 6, curve 8, spiral 10, station equation 6). Max station error 0.0004701052457676269, offset 1.0457828953754054e-7, coordinate 0.0004701052042923065 in source linear units; existing tolerances unchanged.
- Public synthetic example: forward and inverse 2/2, 1e-6 US survey foot tolerance.
- Release simulator packaging checker: icon, version, manifest, acknowledgments, proj.db, absence of developer controls and all sample/validation XML. Incremental stale resources were removed by Xcode on rebuild after adding Release exclusions.
- VeriCivil TypeScript, lint, production build, 19 rendered HTML tests, 12 billing/analytics policy tests, existing superelevation and crushed-stone Pyodide parity.
- Published existing public VeriCivil Site version 35, source 73e94a860272d05b2029dcb1c1930f5a454a2628. Project appgprj_6a5b11395820819190ef498d7c6313cf; deployment appgdep_6ac72275a5ac8191a15e80442841577f succeeded. All four https://vericivil.com/roadstation routes returned 200 without credentials; sample bytes match AppStore/sample.landxml. Existing domain, audience, DB bindings and calculators retained.
- Web finish review scored removal of three heading eyebrows resolved; desktop/mobile support/privacy and landing captures available. This scoped verdict is not device or mailbox validation.

- Physical iPhone 16 Pro Max, iOS 26.6.2: development-signed Release 1.0 (1) smoke passed in 119.661 seconds. Actual Files import, Help/About/acknowledgments, EPSG:6507 confirmation, manual reference result, rename/cold reopen, Field Position and absence of developer controls. Its uniquely named test project was deleted; existing projects retained. Dark appearance observed. This establishes neither surveyed GPS accuracy nor every permission/lifecycle condition.

## In progress / not yet established

Refreshed unsigned Release device archive RoadStation-final.xcarchive succeeded and passed the packaging checker; its executable confirms the observed _stat dependency. This archive is unsigned and is not an App Store upload. Release UI smoke is being run; append its final outcome below. Initial builds ran out of disk; only generated DerivedData/build caches were cleared, while reports/captures were retained. One initial smoke run was interrupted after revealing inherited Help toolbar controls; Help now uses a native sheet with Done. A subsequent run failed because the test swiped the dismissible sheet down; the test now captures Help first and closes acknowledgments with Done directly. Native finish review found no material fixes in normal-text iPhone capture/source scope; dark, large text and VoiceOver remain separate gates.

## User-dependent and device gates pending

Apple enrollment, legal seller identity, Paid Apps Agreement, tax/banking, App Store record/price/availability, distribution team/signing, signed Organizer archive privacy report, upload/processing, TestFlight pilot, review and manual release. support@vericivil.com forwarding alias was created and confirmed in Porkbun after the user signed in. An independent message from the user reached the forwarding inbox; the reply was sent, and the user confirmed receiving it. The support email round-trip passed. no email-hosting purchase or DNS replacement was needed. No App Store link exists yet.

Physical iPhone location/permission/lifecycle/offline/source-replacement/recovery, surveyed known-point checks, iOS 17 runtime, small-screen/landscape/large-text/VoiceOver acceptance and final listing screenshots remain required. Simulator/manual numerical evidence does not establish physical GPS accuracy.

## Evidence locations

Local logs: /tmp/roadstation-{core,apple}-{debug,release}.log, /tmp/roadstation-ord.log, /tmp/roadstation-public-example.log, /tmp/roadstation-release-ui-final.log, /tmp/roadstation-archive-final.log. UI xcresults and unsigned archive: validation-output/phase15/Release and validation-output/app-store (ignored generated artifacts). Website source checkout: /Users/colewinstead/.codex/roadstation-release/vericivil; website published source is retained by Sites. Copy release evidence to durable release storage before clearing temporary logs.
