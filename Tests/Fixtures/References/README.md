# Reference fixture provenance

The following XML files were copied unchanged from the user's supplied projects
on October 2, 2026. Their exporter labels do not make them independent numerical
station/offset benchmarks.

| File | Source | Notes |
| --- | --- | --- |
| cw_reverse_curve.xml | VeriCivil/tests/fixtures/cw_reverse_curve.xml | Local-origin ORD-labelled curve regression |
| sr82_synthetic.xml | VeriCivil/tests/fixtures/sr82_synthetic.xml | Synthetic projected alignment with units and CRS metadata |
| civil3d-road-minimal.xml | LandXML-Road-and-Terrain-GIS-Tools/tests/fixtures/civil3d/road_minimal.xml | Synthetic; spiral endpoint contradicts exact clothoid parameters; rejection expected |
| gis-multiple.xml | LandXML-Road-and-Terrain-GIS-Tools/tests/fixtures/generic/multiple.xml | Two alignments and out-of-scope surfaces |

VeriCivil fixtures carry the repository's MIT license, copyright 2026 Cole
Winstead (same notice as this repository's LICENSE).

GIS reference fixtures are from LandXML Road & Terrain GIS Tools, copyright
2026 Edmond Akello, GPL version 2 or later. The supplied license notice is
preserved in GIS-LICENSE.txt. They are test resources only; no GIS parser or
geometry implementation code was copied into RoadStationCore. Core sources
are original implementations under this repository's MIT license.

Small fixtures outside this directory are authored for RoadStation. The
spiral compound fixture's numbers are independently reproducible with
tools/Generate-SpiralFixture.py (Fresnel series and analytic reversal identity).

Detailed contents, parser diagnostics, provenance qualifications and missing real
ORD spiral/equation coverage: [reference audit](../../../Validation/REFERENCE-FIXTURE-AUDIT.md).
No reference fixture is an independent ORD numerical comparison.
