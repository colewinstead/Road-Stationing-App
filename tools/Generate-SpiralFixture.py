"""Independent reference fixture construction, standard-library Python only.

The small XML fixture is checked in. This helper documents/reproduces its numbers;
Swift tests do not execute Python. Entry clothoid uses a convergent Fresnel series,
exit uses the reversal identity, circle uses analytic trigonometry.
"""
import cmath
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def entry_position(s, length=100, k_end=0.005):
    q = k_end / (2 * length)
    return sum((1j * q) ** n * s ** (2 * n + 1) /
               (math.factorial(n) * (2 * n + 1)) for n in range(32))


def ne(p):
    return f"{p.imag:.14f} {p.real:.14f}"


p0 = 0j
p1 = entry_position(100)
heading1 = 0.25
center = p1 + 200j * cmath.exp(1j * heading1)
p2 = center + (p1 - center) * cmath.exp(0.5j)
heading2 = 0.75
exit_local = cmath.exp(0.25j) * p1.conjugate()
p3 = p2 + cmath.exp(1j * heading2) * exit_local
p4 = p3 + 100 * cmath.exp(1j)

fixture = f'''<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
  <Units><Metric linearUnit="meter" directionUnit="radians"/></Units>
  <Alignments><Alignment name="LSCSL" staStart="1000" length="500">
    <CoordGeom>
      <Line length="100"><Start>0 -100</Start><End>0 0</End></Line>
      <Spiral spiType="clothoid" length="100" radiusStart="INF" radiusEnd="200" rot="ccw" dirStart="0" dirEnd="0.25">
        <Start>{ne(p0)}</Start><End>{ne(p1)}</End>
      </Spiral>
      <Curve rot="ccw" radius="200" length="100"><Start>{ne(p1)}</Start><Center>{ne(center)}</Center><End>{ne(p2)}</End></Curve>
      <Spiral spiType="clothoid" length="100" radiusStart="200" radiusEnd="INF" rot="ccw" dirStart="0.75" dirEnd="1">
        <Start>{ne(p2)}</Start><End>{ne(p3)}</End>
      </Spiral>
      <Line length="100"><Start>{ne(p3)}</Start><End>{ne(p4)}</End></Line>
    </CoordGeom>
  </Alignment></Alignments>
</LandXML>
'''
(ROOT / "Tests/Fixtures/spiral-curve-spiral.xml").write_text(fixture, encoding="utf-8")
for s in [50, 100]:
    print(f"Independent Fresnel at {s}: {entry_position(s)}")
