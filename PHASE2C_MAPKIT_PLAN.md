# Phase 2C — MapKit in Field Position

Date: 2026-10-04. Status: implemented; verification evidence and outstanding
physical checks are in [PHASE2C_MAPKIT_REPORT.md](PHASE2C_MAPKIT_REPORT.md).
Branch: `codex/phase2c-mapkit-field-view`.
Baseline: local `main`, `b808608` (merged field UI changes, PR #6).

## Outcome

Roadway engineers and inspectors see the selected LandXML alignment and their
approximate position over Apple satellite imagery inside the existing Field
Position spatial panel. **Satellite is the default, with a Street Map toggle**,
as confirmed by the user. The station/offset readout, persistent safety status,
collapsible details, CRS confirmation and foreground location lifecycle remain.
This is a geographic display addition, not a change to engineering calculations.

## Confirmed starting points

- `EngineeringCanvas.swift` contains `FieldSpatialView`, explicitly intended as
  the replaceable spatial surface. It currently owns a planar camera and the
  Follow, Recenter and Camera actions controls.
- `FieldPositionView.swift` owns the floating readout, warning overlay, details,
  automatic start/stop and freshness deadline. These remain the screen structure.
- `WorkspaceModel.loadDrawing()` already samples alignments off the main actor
  through `AlignmentSampling.polylines`. Samples are for drawing only, with
  separate polylines for source segments.
- `PROJProjectCoordinateTransformer.geographicCoordinate(from:)` already converts
  project Easting/Northing and explicit units back to WGS84. It rejects height
  inputs and creates a fresh PROJ context/operation for each call.
- `FieldPositionSnapshot` already binds result, coordinate, fix, accuracy, source,
  alignment and confirmed CRS. `FieldPositionSession` remains the location and
  stationing authority.
- Existing UI tests cover automatic location, synthetic injection, browsing
  without stopping location, stale snapshots, background/re-entry and large text.
  Several assertions identify the current field surface as a canvas.

## Screen and interaction contract

Keep the current native SwiftUI composition and system styling (Operate mode).
Replace only the field spatial surface; retain the manual Inspect engineering
canvas and its tap-to-query behavior.

1. Open Field Position: show satellite imagery in a flat, north-up view. Fit the
   selected alignment while waiting for a usable fix. With a fresh completed
   snapshot and Follow enabled, frame the phone and nearest point with context.
2. Draw the selected centerline with a contrasting outline so it remains visible
   over both imagery and street mapping. Preserve source segment boundaries.
3. Draw the snapshot phone marker, approximate accuracy ring, nearest-point
   diamond, dashed offset connector and forward-direction arrow. Ambiguous
   nearest points stay labeled **Representative**. Injected fixes retain their
   DEBUG source label and use the same drawing path.
4. Pan/pinch pauses Follow without stopping location. Follow resumes on the next
   usable snapshot, or immediately if one is current. Recenter moves to the
   displayed snapshot, including a clearly labeled last-known fix, without
   changing Follow. Fit Alignment pauses Follow and fits the whole centerline.
5. Place a native **Satellite / Street Map** picker in Camera actions. Changing
   style preserves camera, Follow, snapshot and location state. Keep the style
   choice in screen state for this phase; each new visit defaults to Satellite.
6. Keep accessible button zoom/pan actions, 44-point targets, VoiceOver summaries,
   Dynamic Type, Dark Mode and Reduce Motion. Camera fitting must account for the
   readout, warning strip and expanded details. Apple attribution and legal
   controls must remain visible and usable.
7. Label the geographic map **North up**, replacing **Grid north is up** only
   for that surface. The engineering fallback retains its grid-north wording.
   Keep pitch and rotation disabled for this phase.

## Implementation approach

### A. Prepare geographic display data

Add a small display helper/model at the Apple boundary, alongside the existing
field-position code. Keep MapKit types in the app target; use existing
`GeographicCoordinate` values for testable conversion output.

- Build an immutable geographic alignment drawing from the existing sampled
  polylines and the explicitly confirmed CRS/project units. For display conversion,
  pass XY-only copies of imported points; do not alter retained source Z values.
- Existing straight segments have only two display samples. Add bounded
  display-only subdivision where the transformed midpoint differs from the
  geographic map chord by more than 0.5 meters. Apply the same check to sampled
  curved segments. This is a drawing tolerance, not stationing/GPS accuracy.
  Fail visibly if the subdivision budget is exceeded; do not silently truncate.
- Validate every converted coordinate, preserve segment identity/order, and
  publish the complete drawing or a clear error. Do not skip failed vertices or
  bridge invalid segments. Detect longitude-wrap crossings before fitting;
  unsupported extents use the engineering fallback rather than fitting a world
  map or drawing an incorrect connecting line.
- Sample/convert off the main actor once per project/source, alignment, CRS and
  unit context. Retain the result for the screen lifetime; GPS updates, style
  changes and camera gestures must not rebuild it. Source replacement and CRS
  changes invalidate it even if the saved project/alignment ID is unchanged.
- Use cancellation and captured-context checks before publishing. Old project,
  alignment or CRS work must never appear after switching context or leaving.
- Profile the real alignment and a larger generated alignment. Start with the
  existing transformer. Add a narrow batch inverse method with one task-owned
  PROJ context only if measured conversion cost requires it; no shared handles,
  global caches, new dependency or backend rewrite.

For each completed `FieldPositionSnapshot`, prepare a separate geographic marker
payload. The phone comes from **that snapshot's** WGS84 sample, not the session's
newest pending sample. Reverse-transform the nearest point and a short point
along the result's forward tangent. Derive the arrow orientation from those
geographic positions: the existing project bearing is relative to grid north.
Use snapshot `horizontalAccuracyMeters` directly for the geographic ring.

Publish the marker group together and only while its source snapshot/context
still matches the readout. During conversion, hide obsolete dynamic markers and
show a small map-overlay loading state; do not pair old markers with a new result.
Conversion failure affects map presentation only, never the valid station result.

### B. Render MapKit within the existing spatial seam

Use native SwiftUI `Map` with `MapCameraPosition`, `MapPolyline`, `MapCircle` and
custom `Annotation` content. Use `.imagery(elevation: .flat)` for Satellite and
`.standard(elevation: .flat)` for Street Map. Use `MapReader` if screen-coordinate
conversion is needed for the forward arrow or to keep markers out of overlays.
Implement this in `FieldMapView.swift`; route to it through `FieldSpatialView`.

MapKit displays the session's supplied markers. Do not add `UserAnnotation`,
`.userLocation` camera tracking, `MapUserLocationButton`, another location manager,
or map-based station calculations. Existing `CoreLocationService` supplies fixes;
existing PROJ and `AlignmentEngine` continue calculating station/offset.

Maintain Follow as explicit screen state. Use user-driven camera changes to pause
it, distinguishing them from programmatic fits and snapshot updates. Preserve
the user's zoom during ordinary follow updates; do not refit the entire alignment
on each callback. Map camera gestures must preserve the navigation back gesture.

### C. Handle blocked and degraded states

| State | Required behavior |
| --- | --- |
| Missing/unconfirmed CRS or unknown units | Existing engineering canvas and setup warning; no geographic alignment overlay or inferred CRS. |
| Confirmed CRS, no fix/permission denied | Geographic alignment remains viewable; no phone/result markers; existing permission/waiting status remains visible. |
| Conversion in progress | Stable readout and controls; drawing/overlay loading status; no mismatched markers. |
| Invalid fix or failed update | Existing retained snapshot rules apply; clearly label last known position and stop following it as current. |
| Stale snapshot | Retain matching map markers with hollow/dashed stale styling; persistent stale warning; no new station calculation or automatic camera move. |
| Poor/approximate accuracy or ambiguity | Existing safety warnings plus matching ring/representative marker; do not imply a unique or survey-grade answer. |
| Alignment/snapshot inverse conversion failure | Clear map-specific error and engineering fallback; do not clear or change valid station/offset. |
| Unavailable imagery/network | Local stationing and overlays remain independent of tiles. Camera actions offers **Engineering View** for a usable grid fallback. |
| Project/CRS/source change, background or screen exit | Cancel obsolete drawing work and clear invalid markers; preserve existing location stop/restart behavior. |

SwiftUI map tile availability is not a stationing readiness signal. Do not infer
tile success from connectivity or add a network monitor. Explain in details that
basemaps may be unavailable offline; offer the engineering fallback without
claiming automatic tile-failure detection or guaranteed offline map storage.
From the fallback, offer **Show Map** when geographic conversion is ready.

## Expected change locations

| Location | Responsibility |
| --- | --- |
| `RoadStationApp/RoadStationApp/FieldMapView.swift` (new) | Native map, style, snapshot markers and geographic camera. |
| `RoadStationApp/RoadStationApp/EngineeringCanvas.swift` | Route field spatial view to map/fallback; reuse planar fallback and existing controls where practical. |
| `RoadStationApp/RoadStationApp/FieldPositionView.swift` | Geographic/grid legend wording and map-specific presentation status as needed. |
| `RoadStationApp/CRSAdapter/Sources/RoadStationFieldPosition/FieldMapGeometry.swift` (new) | Testable display conversion, bounded subdivision and context-safe preparation. |
| Existing CRS/field-position tests | Focused coverage for new display conversion and publication rules. |
| `RoadStationApp/RoadStationAppUITests/RoadStationAppUITests.swift` | Adapt spatial-surface lookup; preserve existing lifecycle/readout checks and add map interactions. |
| Xcode project/test wiring | Register new sources as required by existing project structure. |
| `PRODUCT.md`, READMEs and `PHASE2C_MAPKIT_REPORT.md` | After implementation, document actual behavior and measured verification. |

Do not change portable core geometry, station equations, offset signs, parser,
saved-project schema, quality thresholds or CRS-selection behavior. No MapKit
dependency enters `RoadStationCore` or its Linux/Windows builds.

## Validation and completion gates

1. **Deterministic display checks:** independently known WGS84/project references;
   Easting/Northing axis order; meters/international feet/US survey feet; imported
   Z retained but excluded from display conversion; long projected line
   subdivision; segment gaps; conversion failure; no stale-context publication.
   Check geographic forward direction using a CRS with grid convergence and
   check that all dynamic markers identify the same snapshot as the readout.
2. **Existing numerical regression:** run `swift test`,
   `swift test --package-path RoadStationApp/CRSAdapter`, and the existing
   CROSSGATES CLI validation at its unchanged 0.001 US survey foot tolerance.
   CROSSGATES lacks an explicit EPSG: its numerical cases do not establish map
   placement. Geographic validation needs a separately confirmed CRS/reference.
3. **Simulator build/UI:** run the existing app build, `RoadStationCRSTests`
   scheme and `tools/Test-iOS-Harness.sh <SIMULATOR_UDID>`. Keep the independent
   EPSG:3857 synthetic fix expectation of `STA 100+50.00`, `5.0 ft RT`, and
   `13.1 ft` accuracy. Verify default Satellite, toggle without camera/result
   reset, pan pauses Follow, Recenter preserves Follow, Fit, stale styling,
   fallback, context switching and foreground/background/re-entry. Assertions
   must not depend on Apple tile timing or image content.
4. **Visual/device check:** capture the map and fallback in light/dark mode and
   large Dynamic Type. Verify readout/warnings, markers, controls and attribution
   do not overlap. On a physical iPhone, check real fix cadence, browsing during
   updates, satellite loading and airplane-mode fallback; compare a known point
   using confirmed CRS. Imagery agreement alone is not survey validation.
5. **Performance/evidence:** record vertex count and conversion time for real and
   larger alignments. Demonstrate responsive interaction during preparation and
   no alignment reprojection per fix/style/gesture. Record simulator and physical
   evidence separately; mark unperformed checks as outstanding.

Phase 2C is complete when geographic alignment/snapshot display, camera/style
controls and engineering fallback meet these gates, existing numerical results
remain unchanged, and the report states what was actually verified.

Out of scope: background location, routing/search, map-tap engineering queries,
terrain/3D, station ticks, multi-alignment overlays, offline tile downloads, cloud
sync and changes to project persistence or release/distribution.

## Apple API references

- [Meet MapKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10043/):
  map content, styles, camera interaction and attribution-safe layout.
- [SwiftUI Map](https://developer.apple.com/documentation/mapkit/map): native map
  surface and annotation/overlay content.
- [Imagery style](https://developer.apple.com/documentation/mapkit/mapstyle/imagery(elevation:)):
  satellite imagery style.
- [MapReader](https://developer.apple.com/documentation/mapkit/mapreader): map
  coordinate conversion when needed for display.
- [MapCircle](https://developer.apple.com/documentation/mapkit/mapcircle):
  geographic uncertainty overlay.
