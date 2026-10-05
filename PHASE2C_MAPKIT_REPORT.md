# Phase 2C — MapKit field display

Date: 2026-10-04. Branch: `codex/phase2c-mapkit-field-view`.
Baseline: `b808608`, merged field UI changes. Implementation follows
[PHASE2C_MAPKIT_PLAN.md](PHASE2C_MAPKIT_PLAN.md).

## Behavior

Field Position opens on flat, north-up satellite imagery after explicit CRS
confirmation. Camera actions provides Street Map, Satellite and Engineering
View. Engineering View retains the local project-coordinate grid and offers
Show Map. Map style is screen-local and resets to Satellite on a new visit.
Missing CRS retains the grid/setup workflow; no coordinate system is inferred.

The selected alignment, phone, nearest/representative point, offset connector,
forward arrow and approximate uncertainty circle are geographic display content.
The existing floating station/offset readout, safety status and details remain.
At accessibility text sizes, the readout scrolls within a smaller height budget
so the warning strip and spatial context have room. Regular text retains its
original height budget. The navigation background
keeps labels legible over imagery; the decorative north badge is omitted at large
text sizes, with north-up orientation retained in VoiceOver and details.
The whole details header is tappable, including the empty space between labels.
Follow, Recenter, Fit, zoom and accessible pan actions control the display only.
Pan/zoom/Fit pause Follow; Recenter leaves Follow unchanged. Rotation/pitch are
disabled. Attribution/legal controls remain supplied by MapKit.

All marker data comes from the completed snapshot used by the readout. Pending
marker conversion cannot display obsolete markers alongside a newer result.
Stale/unavailable updates retain clearly labeled matching last-known content;
automatic follow requires a current usable snapshot. Synthetic injection retains
its source label. Map conversion failure falls back to the engineering grid
without changing a valid numerical result.

Basemap loading never gates local stationing. The fallback is available without
automatic tile-failure detection, connectivity monitoring or offline tile storage.
No separate MapKit location feed or user-location annotation is enabled.

## Implementation and numerical boundaries

- `FieldMapView.swift` supplies the native SwiftUI map and routes the existing
  field spatial seam between geographic mapping and `FieldPlanarView`.
- `FieldMapGeometry.swift` produces geographic drawing/marker values outside
  the main actor. Existing alignment samples remain separate per source segment;
  projected segment midpoints receive bounded refinement at a 0.5-meter Mercator
  drawing tolerance. Total display output is capped at 100,000 vertices and
  refinement at 20 levels. Latitude beyond the Mercator display limit and
  longitude-wrap extents explicitly fall back rather than misdraw.
- Source XY and confirmed project units enter the existing PROJ inverse.
  Display conversion excludes height without mutating retained source elevation.
  The forward arrow uses transformed nearest/tangent points, accounting for
  grid convergence. The geographic circle uses the snapshot accuracy in meters.
- Static drawing preparation runs once per view/CRS context, not per fix,
  gesture or style change. Existing saved-project source replacement rebuilds
  the navigation subtree using its source revision; alignment/CRS changes
  recreate the corresponding field context. Cancellation and snapshot checks
  prevent obsolete task results from publishing.
- Profiling justified `geographicCoordinates(from:)`, a narrow batch inverse
  using one call-owned PROJ context/operation. Scalar inverse uses the same
  validation/conversion path. Handles never escape or cross threads; axis/unit
  normalization, missing-grid policy and network-disabled projection are retained.
- Portable Core, parser, geometry, equations, tolerances, offset conventions,
  GPS quality/lifecycle and saved-project schema are unchanged. No dependency
  or MapKit import was added to the portable core.

## Verification

- Root Swift package: **151 tests passed**.
- Apple package: **95 tests passed**, covering existing CRS/catalog/field/saved
  project behavior plus map references, explicit units, retained heights,
  subdivision/gaps, grid convergence, snapshot matching, cancellation, invalid
  batches and scalar/batch parity.
- CROSSGATES ORD: **30/30 passed** at the unchanged **0.001 US survey foot**
  tolerance. Maximum station/coordinate error approximately 0.000470106 feet;
  maximum offset error approximately 0.000000105 feet.
- iOS app Debug simulator build: **passed**, Xcode 27.0 / iOS 27.0.
- iOS CRS target: **94 tests passed** on the iOS 27 simulator (the macOS-only
  profiling test is excluded).
- App UI: **all 11 scenarios verified** on iPhone 18 Pro / iOS 27. The full
  light-mode run passed 9/11; the remaining CRS and saved-project assertions
  accessed collapsed/offscreen content. After revealing that content in the
  tests, the focused dark-mode run passed all 3 selected scenarios, including
  the geographic map. Numerical, lifecycle and frame assertions are retained.
  This covers style switching, snapshot/readout agreement, Follow/Recenter/Fit,
  Engineering View, stale warnings, background/re-entry, largest accessibility
  text, CRS selection, imports/errors, saved-project cold start/rename/delete,
  alignment navigation, manual calculations and station-equation branches.
- Final dark field flow: **passed**, including markers, fallback, preserved
  readout/warning dimensions and background/re-entry. Animated Details transitions
  required waiting for Expanded/Collapsed state and stable bounds before tapping
  again or recording baseline frames; the original one-point frame tolerance is
  unchanged. Satellite, street, fallback and large-text screenshots were inspected.

Local evidence (ignored build artifacts, not release assets):

- Full UI run: `validation-output/phase15/UI-20261004-181056.xcresult`.
- Corrected tests and dark basemap: `validation-output/phase2c/Final-Dark.xcresult`.
- Final dark field flow: `validation-output/phase2c/Field-Dark-Pass.xcresult`.
- Light screenshots: `validation-output/phase2c/satellite-light.png`,
  `street-light.png`, `engineering-light.png`, `large-text-stale.png`.
- Dark screenshots: `validation-output/phase2c/satellite-dark.png`,
  `street-dark.png`, `engineering-dark.png`, `field-details-dark.png`.

Measured macOS Debug drawing preparation (not a device/GPS performance claim):

| Drawing | Vertices | Batch conversion/preparation |
| --- | ---: | ---: |
| First CROSSGATES alignment | 177 | approximately 13 ms |
| Generated 1,000-segment alignment | 2,000 | approximately 22 ms |

Before batching, the real drawing took approximately 2.4 seconds; the earlier
200-vertex generated drawing took approximately 3.3 seconds. CROSSGATES profiling
uses explicit EPSG:6507 as a benchmark assumption; the source lacks an EPSG, so
this does not establish its geographic placement.

## Outstanding physical evidence

The physical iPhone was listed offline during this run. New map behavior,
airplane-mode use, real GPS cadence and known-point geographic placement still
need physical-device verification. Simulator, projection and ORD results do not
establish survey accuracy, imagery accuracy, production distribution or field
positioning accuracy. Only an iOS 27 runtime was available for simulator checks;
the app deployment target remains iOS 17.
