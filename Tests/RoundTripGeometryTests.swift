import XCTest
@testable import RoadStationCore

final class RoundTripGeometryTests: XCTestCase {
    private func check(_ a: Alignment, tolerance: Double = 2e-6) throws {
        let e = AlignmentEngine(alignment: a)
        for fraction in [0.0, 0.01, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.99, 1.0] {
            let d = a.totalGeometricLength * fraction
            let station = try StationingEngine(alignment: a).station(at: d)
            for offset in [0.0, 5, 10, 25, -5, -10, -25] {
                let original = try e.coordinate(station: station, offset: offset)
                let forward = try e.stationOffset(point: original.coordinate)
                XCTAssertFalse(forward.nearestLocationIsAmbiguous, "\(a.name) at \(d), offset \(offset)")
                XCTAssertEqual(forward.geometricDistance, d, accuracy: tolerance, "\(a.name) at \(d), offset \(offset)")
                XCTAssertEqual(forward.displayedStation, station, accuracy: tolerance)
                XCTAssertEqual(forward.signedOffset, offset, accuracy: tolerance)
                let restored = try e.coordinate(station: forward.displayedStation, offset: forward.signedOffset)
                XCTAssertLessThanOrEqual(restored.coordinate.distance(to: original.coordinate), tolerance)
                XCTAssertEqual(forward.longitudinalResidual, 0, accuracy: tolerance)
            }
        }
    }
    func testLineOnly() throws { try check(TestSupport.lineAlignment()) }
    func testLineCurveLine() throws { try check(TestSupport.alignment("tangent-curve-tangent.xml")) }
    func testLineSpiralCurveSpiralLine() throws { try check(TestSupport.alignment("spiral-curve-spiral.xml")) }
    func testClockwiseCurve() throws {
        try check(Alignment(name: "CW", startStation: 1000, geometries: [.circularCurve(TestSupport.curve(clockwise: true))]))
    }
    func testIncreasingSpiral() throws { try check(Alignment(name: "Entry", geometries: [.spiral(TestSupport.spiral())])) }
    func testDecreasingSpiral() throws { try check(Alignment(name: "Exit", geometries: [.spiral(TestSupport.spiral(decreasing: true))])) }
    func testMultipleCurvesORDRegression() throws { try check(TestSupport.alignment("References/cw_reverse_curve.xml"), tolerance: 1e-5) }
    func testLargeCoordinateCompoundRegression() throws { try check(TestSupport.alignment("References/sr82_synthetic.xml"), tolerance: 1e-5) }
    func testEndpointLongitudinalResidualLimitsRoundTrip() throws {
        let e = try AlignmentEngine(alignment: TestSupport.lineAlignment())
        let original = ProjectCoordinate(x: -10, y: 5); let r = try e.stationOffset(point: original)
        let restored = try e.coordinate(station: r.displayedStation, offset: r.signedOffset)
        XCTAssertEqual(restored.coordinate.distance(to: original), 10, accuracy: 1e-12)
        XCTAssertEqual(r.longitudinalResidual, -10, accuracy: 1e-12)
    }
    func testEquationRoundTripsWithExplicitBranches() throws {
        let a = try TestSupport.alignment("station-equations.xml"); let e = AlignmentEngine(alignment: a)
        let stationing = StationingEngine(alignment: a)
        for d in [50.0, 150, 250, 350, 900] {
            let station = try stationing.station(at: d)
            let branch = d < 100 ? 0 : (d < 300 ? 1 : 2)
            let point = try e.coordinate(station: station, offset: -25, branchIndex: branch)
            let result = try e.stationOffset(point: point.coordinate)
            XCTAssertEqual(result.geometricDistance, d, accuracy: 1e-9)
            XCTAssertEqual(result.displayedStation, station, accuracy: 1e-9)
            XCTAssertEqual(result.signedOffset, -25, accuracy: 1e-9)
        }
    }
}
