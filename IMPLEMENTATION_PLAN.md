# Phase 1 implementation plan

Repository inspection: initial Git repository contains only LICENSE. Reference
projects were read, not modified. Their small XML fixtures include an ORD reverse
curve regression, synthetic Civil 3D geometry, surfaces, and multiple alignments.

1. Build a dependency-free Swift package with validated typed models, analytic
   lines/arcs, numerical clothoids, and separate stationing/offset engines.
2. Parse native LandXML, validate geometry, preserve units/metadata, report
   disconnected segments, and reject unsupported or contradictory geometry.
3. Add numerical XCTest coverage, small fixtures, reference-file regressions,
   and a JSON validation runner with JSON/CSV exports and a CLI.
4. Per the user's updated Windows scope, keep all work in the platform-independent
   RoadStationCore Swift package. A future RoadStationApp imports its public APIs.
   Do not create an iOS app or Xcode project on Windows.
5. Run Swift tests at each stage and add Windows/macOS/Linux package CI.

## Risks and decisions

- Convert LandXML N E [Z] to project X=E Y=N exactly once.
- In internal XY, clockwise curvature is negative. Reference GIS code uses NE
  axes, so its angle signs cannot be copied directly.
- Clothoids integrate linear signed curvature without endpoint warping. Check
  declared End and tangent data; reject unsupported spiral types.
- LandXML staInternal is unequated station: distance = staInternal - staStart.
  Validate staBack against preceding branches. Exactly at equations use ahead
  by default; expose back explicitly. Inverse returns all candidates or throws.
- Positive offsets are left (cross(tangent, query-nearest)>0). Endpoint-clamped
  projections may have longitudinal residual and cannot always round-trip;
  expose that residual and nearest-location ambiguity.
- Numeric lengths retain source units; no hidden feet/meter conversions.
- iOS UI/build verification is outside this updated scope. No Apple-only frameworks.
