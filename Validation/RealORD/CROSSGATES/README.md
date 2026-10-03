# CROSSGATES Real ORD Validation

This folder contains the real OpenRoads Designer reference dataset used to
validate RoadStationCore independently of synthetic/unit-test fixtures.

## Files

- `CROSSGATES.xml` — direct LandXML export from OpenRoads Designer; includes
  horizontal geometry, clothoid spirals, circular curves, a station equation
  and the proposed profile.
- `CROSSGATES_HorizontalGeometry_Report.xml` — ORD horizontal geometry report.
- `CROSSGATES_VerticalGeometry_Report.xml` — ORD vertical/profile geometry report.
- `CROSSGATES_StationOffset_Report.xml` — ORD station/offset report.
- `CROSSGATES_TEST_POINTS.xlsx` — independently collected ORD station, offset,
  Northing and Easting values.
- `CROSSGATES-ord-cases.json` — RoadStation validation cases generated from the
  ORD reference values.

## Coordinate convention

- X = Easting
- Y = Northing
- LT = left of increasing station
- RT = right of increasing station
- validation offsets are stored as nonnegative magnitude plus explicit side

The source spreadsheet used ORD's signed-offset convention where negative is LT
and positive is RT.

## Coverage

The case set contains forward coordinate → station/offset and inverse
station/offset → coordinate checks covering real ORD tangents, LT/RT offsets,
CW/CCW circular curves, CW/CCW clothoid spirals, exit-spiral geometry,
station-equation AHEAD/BACK labels at the same physical coordinate, and
post-equation stationing. Expected values come from ORD, not RoadStationCore.

## Run validation

From the repository root in PowerShell:

```powershell
swift run roadstation-validate `
  Validation\RealORD\CROSSGATES\CROSSGATES.xml `
  Validation\RealORD\CROSSGATES\CROSSGATES-ord-cases.json `
  validation-output\CROSSGATES
```

The command prints a PASS/FAIL summary and writes JSON/CSV comparison output.

Current comparison tolerances:

- Station: 0.001 US survey foot
- Offset: 0.001 US survey foot
- Coordinate: 0.001 US survey foot

These are comparison tolerances, not certified field accuracy. Preserve failed
cases and investigate source revision, units, coordinate frame, equation branch
and ORD report rounding before changing a tolerance.

The real ORD comparison must be run and reviewed before Phase 2 GPS/CRS work is
considered unblocked.
