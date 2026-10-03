# Checked-in reference LandXML audit — October 3, 2026

All four XML files under `Tests/Fixtures/References/` were inspected structurally
and imported with the default parser on macOS. Counts below are **XML contents**;
the Civil 3D-labelled file fails import and supplies no usable alignment model.
No checked-in reference file contains independently recorded ORD station/offset
or inverse-coordinate ground truth.

## Provenance and classification

| File | Actual checked source / classification | Exporter evidence |
| --- | --- | --- |
| `cw_reverse_curve.xml` | Byte-identical to `colewinstead/VeriCivil/tests/fixtures/cw_reverse_curve.xml`; real-export-derived regression per supplied provenance/manual review, translated to local origin and stripped of identifying/style metadata | Bentley OpenRoads Designer 24.00.02.25, export date 2026-07-21; header is consistent with source history, not numerical certification |
| `sr82_synthetic.xml` | Byte-identical to `colewinstead/VeriCivil/tests/fixtures/sr82_synthetic.xml`; **synthetic** projected-coordinate fixture | Application explicitly `Synthetic Test Fixture` 1.0 / Test Data |
| `civil3d-road-minimal.xml` | Byte-identical to supplied `LandXML-Road-and-Terrain-GIS-Tools/tests/fixtures/civil3d/road_minimal.xml` in the local Landxml Qgis Plugin checkout; **synthetic** road/terrain fixture | Autodesk Civil 3D label, no version; desc explicitly Synthetic road/surface; no proof of an actual Civil 3D export |
| `gis-multiple.xml` | Byte-identical to supplied `LandXML-Road-and-Terrain-GIS-Tools/tests/fixtures/generic/multiple.xml`; **synthetic** generic regression with small integer coordinates | No Application/exporter/version metadata |

The ORD fixture is useful as a **real exporter regression fixture**, with the
qualification that the checked-in artifact is modified export-derived geometry,
not the original DGN/unmodified export. Original source DGN and recorded ORD
numerical answers are absent. The author's manual review establishes the stated
direction interpretation; it does not establish independently measured station/
offset accuracy. No additional exporter provenance is inferred from XML labels.

VeriCivil source files were checked through the GitHub API, and GIS files against
the supplied local source checkout. Existing license notices remain unchanged:
VeriCivil MIT; GIS fixtures GPL v2 or later (see References/GIS-LICENSE.txt).

## Contents and metadata

| File | Alignment names | Units | Lines | Circular curves | Spirals | Station equations |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `cw_reverse_curve.xml` | ML | US survey foot (`USSurveyFoot`) | 3 | 2 | 0 | 0 |
| `sr82_synthetic.xml` | SR 82 | US survey foot (`USSurveyFoot`) | 3 | 2 | 0 | 0 |
| `civil3d-road-minimal.xml` | Road A | meter | 1 | 1 | 1 | 0 |
| `gis-multiple.xml` | First; Second | international foot (`foot`) | 2 total, 1 each | 0 | 0 | 0 |

Only `sr82_synthetic.xml` has CoordinateSystem metadata:

- name `MDOT-MS83/2011-EF`
- epsgCode `6507`
- horizontalDatum `NAD83(2011)`
- horizontalCoordinateSystemName `MS83/2011-EF`
- desc `NAD83(2011) / Mississippi East (ftUS)`

The other three files contain **no coordinate-system metadata**. Missing metadata
is not evidence of a particular CRS. RoadStation retains the description/name
but performs no CRS interpretation or conversion.

## Actual parser diagnostics

- `cw_reverse_curve.xml`: successful, five segments; alignment warnings none.
  Project warning: `CgPoints data is outside Phase 1 horizontal alignment scope
  and was not imported.` (`CgPoints` is empty, but still present.)
- `sr82_synthetic.xml`: successful, five segments; alignment warnings none.
  Same project CgPoints warning.
- `gis-multiple.xml`: successful, two alignments; alignment warnings none.
  Project warning: `Surfaces data is outside Phase 1 horizontal alignment scope
  and was not imported.`
- `civil3d-road-minimal.xml`: rejected with `Malformed Spiral: Invalid geometry:
  Clothoid parameters disagree with End; residual 0.0051737917723765695 project
  units.` No project is returned, so later Profile/CrossSects warnings are not
  emitted. Those elements and its Surfaces are outside horizontal scope.

## Separate evidence categories and outstanding gaps

1. **Real exporter regression:** the modified ORD reverse-curve fixture checks
   import, line/arc geometry, units, and the numeric direction/tangent agreement.
2. **Synthetic fixture:** SR 82, Civil 3D-labelled minimal road, GIS multiple,
   and the RoadStation-authored fixtures outside References exercise controlled
   geometry and failure handling. Labels do not turn them into exporter evidence.
3. **Independent numerical validation:** the analytic line/circle tests and
   Fresnel-series/reversal benchmarks (including `tools/Generate-SpiralFixture.py`)
   are independent mathematical checks. `validation-cases.json` contains hand
   calculations. These are useful numerical evidence, but **not ORD comparisons**.

**Real ORD spiral validation: MISSING**

**Real ORD station-equation validation: MISSING**

No checked-in genuine/export-derived ORD source contains spirals or station
equations. The only reference spiral is synthetic and invalid. A matching real
ORD export, DGN/reports and independently recorded numeric cases are required.
See `ORD-VALIDATION-PROCEDURE.md` and `ORD-validation-template.json`.
