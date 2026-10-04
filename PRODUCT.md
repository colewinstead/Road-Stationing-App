# RoadStation

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Roadway engineers and inspectors using an iPhone on site to find their station
and left/right offset relative to an imported roadway alignment.

## Product Purpose

Make project alignment stationing usable in the field: import LandXML, confirm
the project's coordinate reference system (CRS), choose an alignment, and read
station and offset alongside the phone location's accuracy and freshness.
Success means a user can reopen a saved project and understand both their
approximate position relative to the alignment and the limits of that result.

## Positioning

RoadStation combines imported horizontal alignment geometry, station equations,
explicit project CRS selection, and foreground iPhone location. Its station and
offset calculations use the shared Swift geometry engine rather than the sampled
line drawn on screen. It does not provide survey-grade positioning.

## Operating Context

- Import `.xml` or `.landxml` through iOS Files. Projects retain an app-owned
  local copy of the source, confirmed CRS and last selected alignment.
- Reopen a saved project, confirm or review CRS readiness, select an alignment,
  and explicitly start Field Position. Location stops when the user stops it,
  leaves that screen, or the app leaves the foreground.
- Browse/search CRS metadata, use one-shot location recommendations, or enter
  an EPSG code manually. A recommendation never confirms a CRS on the user's behalf.
- Supporting tools provide a planar engineering canvas, tap inspection, manual
  coordinate-to-station/offset and inverse queries, metadata and raw results.

## Capabilities and Constraints

- Native SwiftUI iPhone app, currently targeting iOS 17 or later, with a portable
  RoadStationCore calculation engine. The interface is still a developer harness;
  production distribution and field validation are separate milestones.
- Horizontal calculations support lines, circular curves, explicit clothoid
  spirals, multiple alignments and station equations. Unsupported or contradictory
  geometry must be rejected rather than silently substituted.
- Preserve validated geometry, stationing behavior and existing reference
  tolerances. Establish and explain a defect before changing numerical behavior.
- Coordinates are X=Easting and Y=Northing. LandXML Northing/Easting order is
  converted at import. Positive signed offset is LT; negative is RT, relative to
  increasing alignment direction. Displayed station and geometric distance differ
  where station equations apply; ambiguous branches require explicit selection.
- Preserve source units and distinguish meters, international feet and US survey
  feet. CRS and units must be explicit; unresolved CRS or unsuitable units block
  location-based planar stationing. Never guess a CRS from coordinate magnitude.
- Phone GPS is approximate. Keep accuracy, fix age, permission state, ambiguity
  and stale/last-known status visible. Stale or invalid fixes cannot produce new
  calculations; retained snapshots must remain clearly labeled.
- Local saved projects support reopening, renaming, deletion and source
  replacement. Failed replacement must preserve the existing source. Current
  persistence code is in the working tree; older READMEs describe session-only
  storage and must not override this confirmed product requirement.
- Calculations are 2D. Retained elevation metadata does not establish vertical
  profile, slope-distance or elevation-at-offset functionality.
- Geographic maps, background location, cloud sync, accounts, camera/photo
  workflows and App Store availability are not established capabilities.

## Brand Commitments

The product name is RoadStation. Use precise roadway terminology: alignment,
station, offset, LT/RT/ON, Easting/Northing, project units, CRS and EPSG. State
uncertainty plainly and avoid accuracy or distribution claims beyond the evidence.

## Evidence on Hand

- `Validation/RealORD/CROSSGATES/` contains a real OpenRoads Designer LandXML
  export, geometry and station/offset reports, independently collected points,
  and runnable reference cases. Repository reports record 30/30 cases passing
  at 0.001 US survey foot comparison tolerance; this is not certified GPS accuracy
  or a newly verified result from init.
- `Tests/` contains geometry, station-equation, parser and validation checks.
  `RoadStationApp/CRSAdapter/Tests/` covers projection, field position, CRS catalog
  and saved-project behavior; `RoadStationApp/RoadStationAppUITests/` covers app
  workflows. Test presence does not establish current passing status.
- Repository reports record physical iPhone installation and launch, while
  controlled known-point field validation remains outstanding.
- Synthetic fixtures and debug location injection are development aids and must
  remain labeled as synthetic. Do not present them as customer or field evidence.

## Product Principles

1. Make field station and offset the primary job; inspection tools support it.
2. Preserve engineering meaning across import, storage, calculation and display.
3. Keep coordinate-system choices explicit and recoverable.
4. Show uncertainty wherever a position result is shown.
5. Protect local project data and support return visits without repeated import.

## Open Decisions

Specific field accessibility needs, production distribution, pricing and broader
platform support have not been established. No visual direction was chosen during
init.
