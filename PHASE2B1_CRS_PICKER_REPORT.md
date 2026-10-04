# Phase 2B.1 — explicit, searchable CRS selection

Phase 2B.1 replaces primary numeric EPSG entry with a dedicated SwiftUI CRS sheet.
Location supplies recommendations only; **only an explicit Use CRS confirmation
or advanced manual validation changes the session's ConfirmedProjectCRS**.
LandXML identification and geometry are preserved. No MapKit, new projection
formulas, coordinate-magnitude/filename inference, background location, or
production persistence is added. The existing immutable field snapshot,
publication generation checks, stale/last-known retention and CoreLocation
settings remain in place.

## Architecture and source

`RoadStationCRSCatalog` is a new Apple-side Swift package product, outside
RoadStationCore and independent of its geometry implementation. Its immutable
catalog describes horizontal EPSG entries, names, reference-frame/datum names,
unit identities, official areas, projected/geographic type, deprecated status and
optional State Plane jurisdiction/zone. `CRSPickerModel` in the existing
RoadStationFieldPosition module owns asynchronous loading/search and unconfirmed
preview state and a separate one-shot recommendation snapshot. `CRSPickerView` owns presentation; FieldPositionSession owns the
existing backend validation and confirmed CRS. Catalog selection records a
separate **Selected from CRS catalog, confirmed by user** provenance; imported
confirmation retains **Imported from LandXML, confirmed by user**; advanced EPSG
entry retains manual provenance.

The checked-in 2.53 MB `catalog.json` is generated from **the database actually
bundled with NGA projections-ios 3.0.0**:

- EPSG version **v11.004**, date **2024-02-24**.
- Database SHA-256: `199116c89178cbfe1ff954c3f6f77b4ed293a98ed1ec5291fa5dd77c0bc21be1`.
- The database's own PROJ metadata says **9.4.0**; the installed C engine/product
  is the separately pinned **NGA PROJ 9.4.2**, unchanged from Phase 2A. These are
  distinct version records.
- **6,280 Earth horizontal two-axis EPSG entries**, projected and geographic 2D.
  Vertical, geocentric, geographic 3D and compound CRSs are excluded.
- **1,081 State Plane entries**, including datum/unit/deprecated variants,
  covering **all 50 states and 53 jurisdiction labels** with Puerto Rico,
  Puerto Rico & Virgin Islands, and St. Croix.
- State Plane units: **515 US survey foot, 506 meter, 60 international foot**.
  **43 deprecated definitions** remain visible with a warning.

The generator joins authoritative `projected_crs`, `geodetic_crs`,
`geodetic_datum`, `coordinate_system`, `axis`, `unit_of_measure`, `usage`, `extent`,
`ellipsoid`, `celestial_body` and `conversion` records. It stores metadata only;
all projection definitions, axis normalization, transformations and native-to-
project unit scaling continue to come from the unchanged Phase 2A adapter.
Native units use EPSG axis-unit identities 9001/9002/9003, not rounded factors.
Unrecognized/mixed units are explicitly unsupported, never approximated.

Reproduce after resolving the Apple package:

```sh
python3 tools/Generate-CRS-Catalog.py
python3 tools/Generate-CRS-Catalog.py --check
# An alternate proj.db path can be supplied explicitly.
```

`--check` compares the full generated metadata and database checksum with the
checked-in resource without modifying it. macOS CI runs this check after package
resolution. Updating the dependency/database requires regenerating and reviewing
the catalog. NGA and PROJ license notices accompany the metadata resource.

## Exact State Plane membership

Membership does **not** search CRS names for a state substring. It joins each EPSG
projected CRS to its **EPSG conversion identity**, then recognizes these official
conversion families and validates jurisdiction against a complete state/territory
label set:

1. `SPCS83 <jurisdiction/zone>`: 938 entries.
2. `<jurisdiction> CS27 <zone>`: 134 entries, including historical non-NAD27 base
   datums used by EPSG for Hawaii/Puerto Rico.
3. Six curated historical **conversion** codes with exact official-name checks:
   EPSG conversions 10201/10202/10203 (Arizona Coordinate System East/Central/West)
   and 12101/12102/12103 (Michigan State Plane East/Old Central/West). Reuse of these
   conversions across CRSs adds nine entries. The generator asserts the names so
   changes cannot silently broaden membership.

The naming-family approach is tied to the pinned EPSG database and six identity
exceptions; it is not a claim that PROJ has a formal State Plane flag. NGS
publishes the historical State Plane configurations, including replacement of
Michigan's early transverse-Mercator zones; see the [NGS SPCS maps](https://www.ngs.noaa.gov/SPCS/maps.shtml)
and [NGS historical reference](https://www.ngs.noaa.gov/PUBS_LIB/CoordinateCoversionforHydrographicSurveying_TR_NOS114_CGS7.pdf).
UTM, Web Mercator, US National Atlas/Albers and local grids are not included merely
because their names contain a state. Tests protect nationwide counts, Mississippi
identities, historical exception membership and non-State-Plane exclusions.
Guam/American Samoa and newer SPCS2022 systems are not claimed as covered State
Plane families by this pinned index; EPSG horizontal systems remain searchable.

## Installed C API verification

The exact declarations were inspected in the installed
`.build/checkouts/PROJ/src/proj.h`; actual Swift imports/calls compile in macOS
Debug/Release and iOS Simulator. `PROJCatalogInspection` uses:

- `proj_context_create` / `proj_context_destroy`
- `proj_context_set_database_path`, `proj_context_set_enable_network(…, 0)`,
  `proj_log_level(…, PJ_LOG_NONE)`
- `proj_create`, `proj_destroy`, `proj_get_name`, `proj_get_type`
- `proj_crs_get_coordinate_system`, `proj_cs_get_axis_count`,
  `proj_cs_get_axis_info`
- `proj_get_area_of_use`

It obtains the same NGA resource path through existing
`RSProjectionDatabasePath()`. Every inspection owns and destroys its C context
and objects on one thread; no C pointer is cached or crosses actors.
The installed enumeration API `proj_get_crs_info_list_from_database` and
`PROJ_CRS_INFO` were also inspected. Generated database joins were chosen instead
of inspecting thousands of CRS objects every time the sheet opens. The direct
C inspection tests compare EPSG:6507/6510 names, unit code and official bounds
with the generated catalog, verifying the installed dependency boundary.

## Area handling and ranking

Areas retain their official name/description and west/south/east/north WGS84
bounds. Every published usage extent is retained. Containment is inclusive at
boundaries, supports west > east antimeridian ranges, treats −180 and +180 as the
same meridian and handles world-spanning bounds. **These rectangles are not
precise county/zone polygons**. Recommendations never decide a CRS or attach a
numeric confidence/precision score.

The picker owns a **separate CLLocationManager** through
`CoreLocationRecommendationService` / `RecommendationLocationProviding`. Opening
**Choose CRS** automatically calls `requestLocation()` if When In Use or Always
permission already exists. With undetermined permission, opening does not prompt:
**Use My Location** explains “Uses your location once to find nearby State Plane
coordinate systems.” That action requests **When In Use only**, then one location
following authorization. Denied/restricted permission explains why nearby choices
are unavailable; Browse, Search and manual entry remain usable without prompts.
Failure offers an explicit retry; there is no polling or automatic retry loop.

This manager never calls `startUpdatingLocation()` or requests Always permission.
Closing cancels its outstanding one-shot via `stopUpdatingLocation()` on its own
manager, as documented by the installed CLLocationManager SDK. It cannot start or
stop Field Position, station an alignment, enable background location, or confirm
a CRS. Permission is system-wide, but the fix and acquisition state are private
to the picker. Existing live manager settings and callback handling are unchanged.

`LocationSample` and `LocationQualityPolicy` validate the fix **once on arrival**:
invalid coordinates/accuracy/timestamps and initially stale samples are rejected.
Poor or reduced accuracy still produces choices with an approximate warning. A
successful immutable `RecommendationLocationSnapshot` retains coordinates,
accuracy, source and capture time. The list then stays available for the picker
presentation without repeatedly applying live stationing's five-second expiry.
The live stale-data safety classification remains unchanged. Captured one-time
recommendations never claim to track live position. Accuracy is shown in the
project's declared linear units with distinct international/US survey foot names;
unknown project units display meters.

The acquisition status row has a stable scaled height and an always-reserved
spinner slot. It shows **Finding nearby coordinate systems…** while acquiring.
An explicit Refresh Location retains the prior snapshot/list while waiting or on
failure, then publishes the completed replacement. No periodic location-age
refresh, implicit update animation, or layout transition is used in this picker.

For State Plane areas containing the point or lying within a modest **0.05°
angular boundary buffer**, sort by:

1. Official unbuffered containment before nearby boundary candidates.
2. Exact native-project unit identity before convertible units, then incompatible.
3. Current definitions before deprecated definitions.
4. NAD83(2011), NSRS2007, HARN, NAD83, other generations, NAD27.
5. EPSG code for deterministic ties.

The boundary buffer is a recommendation inclusion policy, not a GPS error bound
or a claimed zone polygon. All plausible datum/unit variants stay available;
older systems are not hidden or silently upgraded. Near Mississippi's overlapping
published rectangles both East and West appear. No nearest-zone guess is made.

Exact native unit match differs from **convertible — different native units**.
A metric projected CRS is usable with a foot project when the existing transformer
validates explicit conversion. International and US survey feet never compare
as equal. Geographic angular and unsupported native units cannot be confirmed
for this linear-project workflow; the confirmation disables Use CRS. Backend
validation still runs on explicit confirmation, so metadata alone does not promise
an available accurate datum operation or required grids.

## Selection, warning and UI

Project and Field Position show a compact Choose Coordinate System action and
confirmed name/code/units/provenance. A valid imported EPSG remains prominent and
has its own confirmation action. Nearby choices never replace it.

The dedicated sheet uses the short navigation title **Choose CRS** and has:

- **Recommended**: one-time capture/accuracy/source explanation, multiple ranked
  candidates, area/boundary and compatibility reasons; no-location guidance.
- **Browse**: all State Plane definitions by state/jurisdiction, then zone,
  including datum/version/unit variants and deprecated warnings.
- **Search**: asynchronous token matching of code, official name, state/zone,
  datum and unit aliases. Punctuation is normalized, allowing `NAD83 2011`,
  `survey foot`, `Mississippi West`, `Tennessee`, `6510` and `EPSG:6507`.
- **Enter EPSG manually (advanced)**: the existing validation/provenance workflow.

A row previews a confirmation sheet with official name/code, project/native
units, datum, conversion disclosure and expandable published-area description.
A recommendation reason is labeled **when selected** so it cannot masquerade as
live location after the sample ages. Cancel is always accessible in the toolbar.
Search has explicit Search/Done keyboard dismissal so the result list remains
usable after typing. Only Use CRS invokes FieldPositionSession backend validation. Choosing a different
CRS deliberately invalidates an old live snapshot without changing geometry.

For a fresh live sample outside an imported or selected CRS's official area,
project controls show **Current location appears outside this CRS's published
area of use.** Live warnings retain their freshness policy. The picker and
confirmation use the retained capture and explicitly say **The one-time
recommendation location appears outside this CRS's published area of use.**
Unknown area cannot support either warning. Warnings never change selection.

DEBUG-only `DEBUG fix` injects a clearly labeled recommendation position at
32.3°N, 90.2°W, ±30 m through the same acquisition quality/ranking/warning code.
It cancels any pending picker fix, retains the capture for the sheet and never
transforms or stations the alignment. Injection APIs and UI compile only in
DEBUG. Existing field-position injection remains separate and uses its real
pipeline.

## Performance

A shared actor caches one immutable decoded catalog and precomputed search text
per session. Decode/index construction and search run in detached tasks. Search
revision checks prevent an older asynchronous query replacing a newer query.
SwiftUI List creates rows lazily. The cache contains Swift values only.

Measured on this Apple Silicon Mac (6,280 entries, including final membership):

| Work | Debug | Release |
| --- | --- | --- |
| resource decode + search index | 87.1 ms | 76.8 ms |
| mean search, 100 mixed queries | 17.5 ms | 22.9 ms |

These are observed timings, not performance thresholds or physical-iPhone claims.
The latest simulator run measured 106.6 ms load and 16.4 ms mean search. No GPS polling interval,
callback debounce or artificial calculation delay was introduced.
CLLocationManager does not guarantee a fixed callback cadence; desiredAccuracy,
distanceFilter and activity type influence it but iOS controls delivery. The
existing bestForNavigation, distanceFilterNone and pauses=false settings remain.

## Tests and results

Final validation and evidence are recorded under ignored
`validation-output/phase2b1-one-shot/`. Earlier picker evidence remains in
`validation-output/phase2b1/`. XCTest includes:

- Eight catalog tests: nationwide counts and exceptions, known Mississippi
  EPSG:6507/6510 exact identities/native units/official bounds via compiled C API,
  horizontal filtering and non-State-Plane exclusion, distinct foot units,
  compatible metric conversion, search/no-results, datum/unit/area ranking,
  overlapping boundary candidates, antimeridian/closed bounds and measurements.
- Six picker model regressions added to the FieldPosition suite: opening/
  catalog-only recommendations/preview never confirm or alter live GPS, explicit confirmation,
  imported identity/provenance retention, CRS-change snapshot invalidation,
  fresh/stale/denied/poor-accuracy/debug positions, warnings that never assign CRS,
  and search.
- Thirteen one-shot regressions (12 also in Release): automatic authorized opening,
  both authorization kinds through the actual production adapter, undetermined
  action/When In Use/grant sequence, denied/restricted/denial after action,
  acquisition failure/explicit retry/closed callbacks, fresh capture and retained
  ranking past five seconds without republishing, poor/reduced accuracy,
  rejection of initially stale/invalid fixes, refresh retention/atomic replacement,
  unchanged active/stopped Field Position and transformation call counts, no
  continuous/Always calls, no automatic confirmation and DEBUG cancellation.
- All prior CRS and Phase 2B permission/calculation/snapshot/stale/out-of-order/
  callback tests remain. Independently sourced NGA transformation cases remain.
- UI tests cover opening, a DEBUG recommended EPSG:6510, explicit Use CRS,
  Mississippi West search and confirmation, and advanced manual EPSG:3857.
  Existing invalid EPSG, live injection, fresh → stale/last-known → fresh stable
  card frame, Files imports/errors and geometry harness tests remain.

| Check | Result |
| --- | --- |
| Root Swift Debug | 151 core + 6 harness tests passed |
| Root Swift Release | 151 core + 6 harness tests passed |
| Apple package Debug | 12 CRS + 46 field/picker + 8 catalog passed |
| Apple package Release | 12 CRS + 44 field/picker + 8 catalog passed |
| iOS RoadStationCRSTests | 66/66 passed, 0 skipped |
| RoadStationApp Debug simulator build | succeeded |
| Full UI suite | 7/7 passed, including updated one-shot picker case |
| CROSSGATES real ORD | **30/30 passed**, unchanged **0.001 US survey foot** |
| Reproducible catalog check | passed |

The updated picker UI case verifies the full **Choose CRS** title, retained
recommendations beyond six seconds, unchanged status-text frame, visible accuracy,
explicit EPSG:6510 confirmation, nine Mississippi West search results and manual
EPSG:3857 fallback. All six existing UI regressions passed in the same completed
run. The retained-capture screenshot shows ±98.4 US survey feet for the injected
30 m accuracy, capture time, approximate warning and State Plane choices, with
no clipped title. Permission/failure/active-session isolation is exercised by
controlled providers and the production manager seam rather than real GPS.
Physical-device delivery and permission prompts still need an iPhone retest.

Latest one-shot evidence:

- `core-debug.log`, `core-release.log`, `apple-debug.log`, `apple-release.log`,
  `ios-crs.log`, `app-build.log`, `crossgates.log`, `catalog-check.log` under
  `validation-output/phase2b1-one-shot/`.
- iOS unit bundle: `validation-output/phase2b1-one-shot/CRS.xcresult` (66 passed).
- Full UI bundle: `validation-output/phase15/UI-20261003-232404.xcresult`
  (7 passed), with its command log at `validation-output/phase2b1-one-shot/ui.log`.
- Retained-capture/confirmation/search/selection screenshots exported to
  `validation-output/phase2b1-one-shot/picker-screenshots/`; retained capture
  inspected visually. Earlier picker images remain in the prior output folder.

CROSSGATES retains station error max 0.0004701052457676269, offset error max
1.0457828953754054e-7 and coordinate error max 0.0004701052042923065 US survey foot.
Core geometry, parser, CRS models, validated ORD inputs and production transformer
files have no diff from merged Phase 2A `origin/main`.

CI now runs catalog tests automatically in the Apple package and iOS CRS scheme,
checks generation reproducibility, adds Apple Release testing, and runs both
focused CRS picker and live-field UI cases with diagnostics collection disabled
(as in the existing local harness) and bounded test execution, using a portable available iPhone
name/OS destination. The full Files suite still uses the local helper to stage
fixtures. Local tests use iPhone 18 Pro/iOS 27.0/Xcode 27.0.

## Changed files and limits before MapKit

New files: `RoadStationCRSCatalog/CRSCatalog.swift`, its generated JSON/license
resources, `tools/Generate-CRS-Catalog.py`, `CRSCatalogTests.swift`,
`RoadStationFieldPosition/CRSPickerModel.swift`,
`RoadStationFieldPosition/RecommendationLocationService.swift`, app `CRSPickerView.swift`, and this
report. Integration edits: Apple `Package.swift`, Xcode product/source/test wiring,
`FieldPositionView.swift` CRS controls, FieldPositionSession explicit catalog
confirmation, LocationTypes provenance/status copy, FieldPositionTests, harness
UI tests, CI and README files. Earlier Phase 2B live-position and smoothing edits
remain in the same working branch and are described in PHASE2B_LOCATION_REPORT.md.

Before maps, validate the picker on physical iPhones with real design CRS records,
large Dynamic Type, permission/precision transitions and field accuracy. The user
reported physical-device stationary callbacks around 4–6+ seconds; the retained
snapshot now stays visible as explicitly stale/last-known at the unchanged
five-second threshold. Corrected physical-device behavior still needs verification.

Bounding-box recommendations can include wrong county zones; confirmation against
design records is essential. The pinned database is not a latest-EPSG/SPCS2022
claim. Non-EPSG authorities and unsupported axis units are outside catalog scope;
manual EPSG handles valid horizontal choices absent from generated metadata.
Availability/accuracy of datum operations and grids retain Phase 2A limitations.
There is no CRS persistence, vertical transformation, automatic datum upgrade,
map, background location, or survey-grade accuracy claim.
