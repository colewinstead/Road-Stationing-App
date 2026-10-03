RoadStation CROSSGATES real-ORD validation

1. Copy these files into your Road-Stationing-App checkout, for example:
   Validation/RealORD/CROSSGATES.xml
   Validation/RealORD/CROSSGATES-ord-cases.json

2. From the repository root run:

swift run roadstation-validate \
  Validation/RealORD/CROSSGATES.xml \
  Validation/RealORD/CROSSGATES-ord-cases.json \
  validation-output/CROSSGATES

3. Review the console summary and the generated CSV/JSON outputs.

Expected source convention:
- X = Easting
- Y = Northing
- negative ORD offset in the spreadsheet = LT
- positive ORD offset in the spreadsheet = RT
- validation JSON stores offset magnitude + explicit side

The JSON contains 30 cases:
- forward coordinate -> station/offset
- inverse station/offset -> coordinate
- explicit station-equation AHEAD and BACK cases at the same physical coordinate

Tolerances are 0.001 US survey foot for station, offset, and coordinate comparison.
