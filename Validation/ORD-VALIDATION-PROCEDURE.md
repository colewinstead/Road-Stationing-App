# Collect independent OpenRoads Designer validation values

Phase 1 is ready to collect comparison data. **Phase 2 remains blocked until real
ORD numerical comparison has been performed.** RoadStation outputs are never
acceptable expected values. Obtain every expected station, offset and coordinate
from Bentley ORD using the same DGN alignment revision that produced the XML.
This procedure is a proposed collection workflow; it has not been executed in
ORD during this audit. Ribbon labels may vary with ORD version/workspace.

## 1. Freeze the source and precision

1. Open the source DGN in ORD and record the installed version, DGN filename,
   model, alignment name, revision/date, linear units and coordinate-system
   description. Export that horizontal alignment to LandXML using ORD. Preserve
   the export unchanged, and record its filename (preferably SHA-256 as well) in
   your collection notes. Do not collect from a different revision.
2. Work in the **horizontal plan model**. All inputs are horizontal Easting and
   Northing, station along the horizontal alignment, and horizontal perpendicular
   offset. Do not use latitude/longitude, slope distance, profile stationing or
   terrain elevations. No CRS transformation or unit conversion occurs here.
3. Confirm that ORD's plan coordinates match the exported XML coordinate frame.
   The checked-in `cw_reverse_curve.xml` was translated to a local origin. Its
   coordinates cannot be compared directly to an original projected DGN. Obtain
   a matching unmodified export for the real comparison, or a corresponding ORD
   model in exactly that local frame. Do not infer a transformation in RoadStation.
4. Generate the horizontal geometry report for the selected civil alignment,
   through its context menu/report command. Retain PC/PT, TS/SC/CS/ST, element
   lengths, equation locations, back/ahead labels and coordinates. In Bentley
   Civil Report Browser, use **Tools > Format Options** to increase station,
   linear and Northing/Easting precision. Save the report, including its header.
5. Retain **at least six decimal places**, preferably eight or full exported
   precision, for Easting, Northing, station and offset in project units. If ORD
   only exposes fewer digits, record that limitation; do not append invented
   precision. Retain substantially more precision than a future mobile display.
   Template tolerances of `0.001` are proposed comparison thresholds in source
   units, not certified accuracy. Agree them before seeing the errors, accounting
   for report rounding. Do not enlarge them merely to obtain PASS.

Bentley's [Analyze Point instructions](https://bentleysystems.service-now.com/community?id=kb_article_view&sysparm_article=KB0019028)
identify the ORD command below. Its
[Civil AccuDraw station/offset demonstration](https://bentleysystems.service-now.com/community?id=kb_article_view&sysparm_article=KB0019765)
supports precise placement relative to a selected civil element. Bentley also
documents [Civil Report Browser format options](https://bentleysystems.service-now.com/community?id=kb_article_view&sysparm_article=KB0021864)
(the latter article is for InRoads; confirm those shared report-browser options in
your installed ORD version).

## 2. Forward: coordinate to station/offset

1. Choose an exact point from the ORD geometry report, or create a named test
   point in a validation copy of the DGN. Use coordinate entry or a precise snap,
   rather than a free cursor location. Record the actual point Easting/Northing
   from ORD's point/element properties or coordinate report.
2. In the **OpenRoads Modeling** workflow choose **Home > Model Analysis &
   Reporting > Civil Analysis > Analyze Point**. Select the complete horizontal
   civil alignment, then snap to the exact test point. Verify the alignment name
   and increasing-station direction. Record the ORD station, offset magnitude
   and LT/RT indication. If the dynamic readout lacks sufficient precision, use
   a point/geometry report with the increased precision or document the shortfall.
3. For tangent midpoint and cardinal points use zero offset. For LT and RT
   tangent cases use distinct named points at useful nonzero offsets. Repeat
   nonzero offsets on curve/spiral interiors once those sources are available.
   Confirm whether the displayed offset sign represents LT or RT; retain the
   literal ORD label in your notes rather than relying on a screen orientation.
4. In the JSON record use `inputCoordinate: {"x": EASTING, "y": NORTHING}`,
   numeric `expectedStation`, nonnegative `expectedOffset`, and `expectedSide`
   `"LT"`, `"RT"` or `"ON"`. ON requires an expected magnitude of zero.
   Forward comparison treats an actual offset within `offsetTolerance` as ON
   to accommodate report rounding. Engine ON classification continues to use
   its configured geometry coordinate tolerance.
   Existing signed-only cases remain valid when `expectedSide` is omitted:
   positive offset means LT, negative offset means RT.

## 3. Inverse: station/offset to coordinate

1. Select an ORD-reported station and an offset magnitude/side, recording the
   equation branch/prefix when relevant. In a validation DGN copy, start a civil
   point or line placement command and enable **Civil AccuDraw Station/Offset**.
   Select the intended horizontal alignment as the origin/reference for both
   station and offset; keep the ordinates linked to the same alignment.
2. Enter and lock the station and offset with the intended side, then accept the
   point. Resolve any station prefix/branch prompt in ORD. Verify the resulting
   point with Analyze Point before recording its Easting/Northing from ORD
   properties or a coordinate report at full available precision.
3. Record `inputStation`, nonnegative `inputOffset`, `inputSide: "LT"|"RT"|"ON"`,
   and `expectedCoordinate: {"x": EASTING, "y": NORTHING}`. Alternatively omit
   `inputSide` and supply positive-left signed `inputOffset`. Do not combine an
   explicit RT side with a negative magnitude; the runner rejects that conflict.
4. Choose offsets in a unique local normal neighborhood. At intersections,
   sharp corners, overlaps, or beyond curve centers the nearest location may
   not be unique; record those separately rather than expecting a normal round trip.

## 4. Station equations and geometry coverage

The template has 16 locations, each with one forward and one inverse slot:

| Locations | How to select them in ORD |
| --- | --- |
| Tangent midpoint, zero; tangent LT; tangent RT | Choose an interior tangent station in ORD; create points using ORD Station/Offset |
| PC, curve midpoint, PT | Use reported PC/PT and an interior arc station from ORD |
| TS, entry spiral midpoint, SC | Use ORD's entry-clothoid endpoints and interior station |
| CS, exit spiral midpoint, ST | Use ORD's exit-clothoid endpoints and interior station |
| Immediately before equation; back; ahead; immediately after | Use equation report and precise ORD Station/Offset placement on each branch |

Use **horizontal arc-length midpoints**, obtained in ORD, rather than the straight
chord midpoint. At shared cardinal points use the incoming element convention;
check tangent continuity in the ORD report. For equation cases, record the same
physical equation coordinate with both ORD back and ahead labels. Before/after
points must be at distinct physical distances, e.g. 0.01 project units before
and after (well beyond your chosen 0.001 comparison tolerance); record the actual
ORD values rather than substituting those illustrative distances as answers.

Copy the ORD station prefix/branch name and equation back/ahead pair into
`description` and the source notes. For inverse lookup, set `branchIndex` to the
zero-based branch in increasing geometric distance: branch 0 before the first
equation, branch 1 after the first, and so on. At an equation, back uses the
preceding branch and ahead uses the following branch. Overlapping station labels
need this explicit branch. JSON station values exclude the ORD prefix and `+`:
425+37.28 is numeric 42537.28. Keep the original formatted label in the notes.

Forward equation-limit slots use `equationSide: "back"` or `"ahead"`. This is an
explicit validation-only selection: the projected distance must be within
`stationTolerance` of exactly one equation. The selected equation label plus the
projection's distance residual is compared, so rounded coordinates do not hide
station error. Ordinary forward queries remain right-continuous (ahead exactly
at the equation); immediately-before/after cases must omit `equationSide`.
Inverse lookup uses `branchIndex`, not `equationSide`.

**Real ORD spiral validation: MISSING**

**Real ORD station-equation validation: MISSING**

The checked-in export-derived ML regression has neither geometry type. Obtain
an actual ORD export containing explicit clothoids and a source with station
equations (one or multiple files) and their matching DGN/reports. Leave missing
slots null and retain their `_missingSourceData` notes. Do not construct synthetic
XML and call it real exporter validation. No independent ORD numeric results
have been collected for even the existing line/arc fixture yet.

## 5. Populate and run

1. Copy `ORD-validation-template.json` to a collection file. Fill the exact
   `alignmentName`, `referenceSoftwareVersion`, `referenceSource` (DGN revision,
   report, collection date), `sourceLandXML` and `description` for each case.
   Each run consumes one XML; use separate case files for separate exports.
2. Enter independently recorded values in the nullable fields. Keep missing
   cases in the collection/template file. Copy **only completed cases** to a
   separate runnable JSON array, e.g. `Validation/ORD-collected-cases.json`.
   Remove advisory `_status`/`_instructions` fields from completed cases if useful.
   Unpopulated cases FAIL; an empty file is an error. None can count as validation.
3. Run from the repository root:

   ```sh
   swift run roadstation-validate Validation/your-real-export.xml \
     Validation/ORD-collected-cases.json validation-output/ord-comparison
   ```

   Default direction convention is east-origin/counterclockwise, retained for
   the manually reviewed ORD fixture. For a demonstrated alternate exporter use
   `--directions north-ccw` or `--directions north-cw`; do not guess/invert rotation.
4. Inspect both exports and the console: Cases, Passed, Failed, maximum absolute
   station/offset errors and maximum Euclidean coordinate error. CSV/JSON retain
   metadata, input/expected/actual values and error differences. Category counts
   are based on your recorded `category` (`line`, `curve`, `spiral`,
   `stationEquation`). N/A means no numeric comparison, not zero error.
   Return codes: 0 all PASS, 1 case failure, 2 usage/import/IO error.
5. Investigate failures against the original ORD point and report: revision,
   units, coordinate frame, side, branch and precision first, then geometry.
   Preserve failing cases. Retain the exact XML, populated JSON, raw ORD reports,
   output files and source revision together for review. Phase 2 stays blocked
   until an engineer reviews the real ORD comparison, including the missing
   spiral/equation coverage; passing synthetic cases cannot satisfy that gate.
