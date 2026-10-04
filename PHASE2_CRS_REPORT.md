# RoadStation Phase 2A CRS report

Date: 2026-10-03. Phase 2A implements CRS architecture and explicit-coordinate
transformations. Live CoreLocation, MapKit, and a production CRS picker are not
implemented. No validated alignment/station/offset geometry or tolerance changed.

## Architecture

- `RoadStation/Core/CRS` contains portable geographic coordinates, EPSG identity,
  resolution/readiness, output units, typed errors, and the bidirectional
  `ProjectCoordinateTransformer` protocol. It uses no Projections, `proj`,
  CoreLocation, or MapKit imports. The root package retains its dependency-free
  core and existing CLI/harness targets.
- `RoadStationApp/CRSAdapter` is a separate Apple-only Swift package. Its
  `PROJProjectCoordinateTransformer` implements the core protocol. The Xcode app
  links its `RoadStationAppleCRS` product alongside the installed NGA product.
- Each adapter call owns and destroys a separate PROJ context and normalized
  operation. The adapter is an immutable `Sendable` value; C pointers and mutable
  backend state never cross threads. Global PROJ defaults are not modified.
- Import adds CRS identification metadata only. Geometry retains all original
  coordinates, heights, lengths, stations and offsets. The app checks readiness
  off the main actor and displays it with project metadata. It does not transform
  the imported alignment or send degree coordinates to the planar engine.

## Dependency integration and compiled API verification

Installed/resolved dependencies, verified by actual macOS compilation and the
RoadStationApp iOS Simulator build:

| Package | Version | Product / imported module | Revision |
| --- | --- | --- | --- |
| NGA projections-ios | 3.0.0 | `Projections` / `Projections` | `f05c424664072bbc9bd177c62f82368b08414253` |
| NGA PROJ | 9.4.2 | `proj` / `proj` | `336fced3634f438f81e0d435ad99658688d1cf71` |
| NGA coordinate-reference-systems-ios | 2.0.0 | `CoordinateReferenceSystems` (transitive) | `d0d8cd34710aa78adb1bef3cdb2bf09a18356fa0` |

The Apple package pins projections-ios and PROJ exactly. Both its
`Package.resolved` and the Xcode workspace lockfile record the dependencies.
The user's existing NGA app-target integration and app scheme settings were
preserved. The app's local package reference and dedicated `RoadStationCRSTests`
target/shared scheme were added for simulator adapter verification.

Source headers and implementations in the installed checkout were inspected
before use. Swift tests compile `import Projections`, `import proj`,
`PROJIOUtils.databasePath()`, and `proj_info()`. Tests load the actual bundled
NGA database and verify PROJ major/minor 9.4 on macOS and iOS Simulator.

The high-level NGA factory raises Objective-C exceptions for invalid definitions
and its transformation wrapper keeps operation handles private. The adapter
therefore uses NGA's bundled `proj.db` with the C `proj` product supplied by its
SPM dependency. This gives explicit axis normalization, units, return-code checks
and Swift errors. A small Objective-C resource bridge catches NGA's missing
resource exception and returns nil, which becomes `.backendUnavailable`.
No replacement system PROJ install or separately generated database is used.

Compiled C calls include `proj_context_set_database_path`, `proj_create`,
`proj_get_type`, `proj_crs_get_coordinate_system`, `proj_cs_get_axis_info`,
`proj_create_crs_to_crs_from_pj`, `proj_normalize_for_visualization`,
`proj_trans` with `PJ_FWD`/`PJ_INV`, and the corresponding destroy/error APIs.

## CRS model and readiness

`GeographicCoordinate` stores WGS84 latitude/longitude in degrees. Its throwing
initializer rejects non-finite values, latitude outside [-90,90], and longitude
outside [-180,180]. Boundary values are accepted; values are not wrapped.
It deliberately contains no height or epoch.

`CoordinateReferenceSystem` stores an explicit positive EPSG code and exposes a
canonical `EPSG:<code>` identity. Syntactic validity does not imply that the
backend contains that code. `CRSResolution` distinguishes explicit identification
from unresolved missing/invalid identification. `CRSReadiness` distinguishes
unresolved, unavailable with a typed error, and a backend-checked `ResolvedCRS`
containing native/output units. Ready means an operation could be created, not
that every input lies in its domain or that field accuracy is established.

LandXML reads only the explicit `CoordinateSystem/@epsgCode` attribute (decimal
code or `EPSG:<code>`). Missing identification remains unresolved, even if a
name/description sounds like a CRS. Invalid identification remains unresolved
with the original value. Descriptions remain display metadata. Filename,
coordinate magnitude, horizontal datum, and unit never supply a CRS guess.
Other vendor CRS identifiers/WKT are outside this initial import interpretation.
CROSSGATES lacks an explicit EPSG identification and remains unresolved.

The transformer cannot initialize from an unresolved project. A future explicit
user selection can provide `.identified(...)`; nothing chooses a default CRS.
The app requests output in the project's declared linear unit. Geographic CRS
with linear project units, or unknown project units, are unavailable.

## Axis handling

WGS84 input is passed explicitly as longitude=X, latitude=Y in degrees.
The backend operation is always passed through
`proj_normalize_for_visualization`; authority ordering is not implicitly assumed.
The normalized destination CRS is inspected separately: it must have two axes,
first east and second north. Projected results are always X=Easting,
Y=Northing. Inverse operations use the same normalized operation with `PJ_INV`.
See [PROJ's API documentation](https://proj.org/en/stable/development/reference/functions.html)
and [C API quick start](https://proj.org/en/stable/development/quickstart.html).

EPSG:4326 identity is explicitly supported with `.degree` output, X=longitude
and Y=latitude. Degree output is an interchange/test capability and must never
enter RoadStation's planar station/offset engine. There is no geographic-to-foot
identity conversion.

There is no destination EPSG allowlist: the adapter queries the bundled database
for arbitrary codes. The current horizontal contract accepts 2D geographic and
projected definitions with supported units and normalized east/north axes.
Geocentric, 3D, vertical and compound definitions are rejected. Unusual polar,
oblique, south/west axes are rejected rather than mislabeled as Easting/Northing.

## Units

Native axis unit identity and SI conversion factor are read from PROJ, not inferred
from EPSG number, coordinate magnitude, description or a generic `ft` label.
Both axes must agree. Supported native linear identities are EPSG 9001 (metre),
9002 (international foot), and 9003 (US survey foot). EPSG 9102/9122 represent
degrees; the actual EPSG:4326 axis metadata uses 9122.

| Project unit | Meters per unit |
| --- | --- |
| meter | 1 |
| international foot | 0.3048 exactly |
| US survey foot | 1200/3937 exactly |

Forward output multiplies native values by
`nativeMetersPerUnit / projectMetersPerUnit`; inverse input divides by the same
factor. Conversion is confined to the adapter boundary. Native international
foot and survey foot are distinct identities and are never silently equated.
Unknown units and angular/linear mismatches fail. Heights are not transformed:
forward returns nil Z; inverse rejects a supplied Z rather than discarding it.

## Tests and verification

The root package passes **151 core tests** (142 existing + 9 CRS model/import
cases) and **6 existing harness helper tests**, in Debug and Release. The Apple
adapter passes **12 tests on macOS and 12 on the iOS Simulator**. Test source is
shared between its SPM test target and the Xcode unit-test target.

Coverage includes valid/range/non-finite geographic input, explicit EPSG identity,
invalid/unsupported codes, unresolved import, no CRS inference, source geometry
preservation, identity degrees, authority axis ordering, forward/inverse checks,
round trips across northern/southern UTM and Web Mercator, native metre/foot/US
survey foot, all project output units, incompatible/unknown units, non-finite
project input, invalid inverse degree ranges, supplied height and domain failure.

Two externally published known-reference cases are fixed test constants, never
generated by RoadStation:

1. WGS84 (1°E,1°N) ↔ EPSG:3857: E=111319.49079327357 m,
   N=111325.14286638486 m, from
   [NGA's version 3.0.0 Swift reference test](https://github.com/ngageoint/projections-ios/blob/3.0.0/proj-iosTests-swift/PROJSwiftReadmeTest.swift).
   Tolerance is 1e-7 m forward and 1e-12 degrees inverse.
2. WGS84 (12°E,55°N) ↔ EPSG:25832: E=691875.63214 m,
   N=6098907.82501 m, using
   [OSGeo's published GRS80 UTM zone 32 reference](https://github.com/OSGeo/PROJ/blob/9.4.1/test/gie/more_builtins.gie).
   Tolerance is 0.001 m forward and 1e-8 degrees inverse. This verifies the
   adapter against an external expected value; it is not an independent
   certification of PROJ or survey accuracy of the WGS84/ETRS89 datum operation.

EPSG:3035 tests directly assert the native Northing/Easting directions, then
verify normalized E=4321000 m/N=3210000 m at 52°N,10°E and its inverse.

Executed commands:

```sh
swift test
swift test -c release
swift test --package-path RoadStationApp/CRSAdapter
swift run roadstation-validate \
  Validation/RealORD/CROSSGATES/CROSSGATES.xml \
  Validation/RealORD/CROSSGATES/CROSSGATES-ord-cases.json \
  validation-output/CROSSGATES
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj \
  -scheme RoadStationApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=7A82DB49-90F0-4BBF-8978-8CC72F9988F1' \
  -derivedDataPath validation-output/phase2a/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj \
  -scheme RoadStationCRSTests -configuration Debug \
  -destination 'platform=iOS Simulator,id=7A82DB49-90F0-4BBF-8978-8CC72F9988F1' \
  -derivedDataPath validation-output/phase2a/DerivedData \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Xcode 27.0 (27A266a), iPhone 18 Pro simulator, iOS 27.0. App build succeeded.
The build emits the routine AppIntents metadata warning because that framework
is not used. Logs/results are under ignored `validation-output/phase2a/`.
CI includes Apple adapter tests on the existing macOS job; Linux continues
building/testing the independent core. The iOS job retains the RoadStationApp
simulator build and also runs the RoadStationCRSTests scheme with parallel
testing disabled and ad hoc signing enabled. It discovers an available iPhone
from the newest installed available iOS runtime and constructs a name/OS
destination at runtime; no simulator UUID or model is hard-coded.

### Real ORD regression

**CROSSGATES: 30/30 passed, 0 failed**, retaining the original 0.001 US survey foot
station, offset and coordinate tolerances:

| Category | Passed |
| --- | --- |
| line | 6/6 |
| curve | 8/8 |
| spiral | 10/10 |
| station equation | 6/6 |

Maximum station error: 0.0004701052457676269 US survey foot.
Maximum offset error: 1.0457828953754054e-7 US survey foot.
Maximum coordinate error: 0.0004701052042923065 US survey foot.
Output is `validation-output/CROSSGATES.json` and `.csv`. The validated geometry
sources, alignment parser, ORD inputs and tolerance definitions have no diff.

## Known limitations

- Horizontal 2D only; no height, vertical datum, geoid, coordinate epoch, or
  time-dependent transformation contract.
- Supported native units are metre, international foot, survey foot and degree.
  Other native units and unusual axes fail explicitly, even if PROJ contains
  the CRS. No custom WKT, PROJ strings, or non-EPSG authorities yet.
- Network/grid downloads are disabled. `ALLOW_BALLPARK=NO` and `ONLY_BEST=YES`
  prevent silent approximate datum fallback. Missing required grids/operations
  cause an availability or transform error. Not every EPSG pair can be used
  with the database alone. Readiness is not point-specific grid/domain validation.
- EPSG definitions and available datum operations do not establish engineering
  accuracy. Area-of-use policy, operation accuracy/selection reporting, grid
  provenance and field validation remain future work.
- Per-call context/operation creation favors simple ownership over live-update
  performance; sustained CoreLocation rates have not been benchmarked.
- No device/field location testing, permission handling, production CRS picker,
  persistence, MapKit integration or live stationing is claimed for this phase.

## Next Phase 2B step

Build explicit project CRS selection/confirmation that preserves import
identification and user-choice provenance, including project unit compatibility.
Keep unresolved projects blocked from geographic conversion. Then add the app-side
CoreLocation boundary, accuracy/staleness gating, visible operation/error status
and controlled known-point checks before enabling live station/offset queries.
The existing core geometry should continue to receive only finite Easting/Northing
values in the project's unchanged linear units. MapKit remains a separate display
integration; neither location nor maps belong in RoadStationCore.
