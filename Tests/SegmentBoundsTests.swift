import XCTest
@testable import RoadStationCore

final class SegmentBoundsTests: XCTestCase {
    func testExactLineBoundsAndLowerDistance() throws {
        let line = try LineSegment(start: .init(x: 1, y: 5), end: .init(x: 11, y: 25))
        XCTAssertEqual(line.bounds.minX, 1); XCTAssertEqual(line.bounds.maxY, 25)
        XCTAssertEqual(line.bounds.distance(to: .init(x: -2, y: 1)), 5, accuracy: 1e-12)
    }
    func testArcBoundsIncludeCardinalExtrema() throws {
        let c = try TestSupport.curve(startAngle: 350 * .pi / 180, sweep: 220 * .pi / 180)
        for i in 0...1000 { XCTAssertTrue(c.bounds.contains(try c.point(at: c.length * Double(i) / 1000))) }
        XCTAssertEqual(c.bounds.maxX, 100, accuracy: 1e-6); XCTAssertEqual(c.bounds.minX, -100, accuracy: 1e-6)
        XCTAssertEqual(c.bounds.maxY, 100, accuracy: 1e-6)
    }
    func testSpiralConservativeBoundsContainCurve() throws {
        for s in [try TestSupport.spiral(), try TestSupport.spiral(decreasing: true), try TestSupport.spiral(clockwise: true)] {
            for i in 0...1000 { XCTAssertTrue(s.bounds.contains(try s.point(at: Double(i) / 10))) }
        }
    }
    func testBoundsPrunedSearchMatchesFullSegmentSearch() throws {
        let a = try TestSupport.alignment("spiral-curve-spiral.xml"); let e = AlignmentEngine(alignment: a)
        for i in 0..<100 {
            let q = ProjectCoordinate(x: Double((i * 137) % 700) - 200, y: Double((i * 57) % 500) - 150)
            let result = try e.stationOffset(point: q)
            let brute = try a.segments.map { try $0.geometry.closestPoint(to: q).queryDistance }.min()!
            XCTAssertEqual(result.distanceFromQueryPointToAlignment, brute, accuracy: 1e-7)
        }
    }
    func testCustomInvalidToleranceRejected() throws {
        var t = GeometryTolerances(); t.integration = .nan
        XCTAssertThrowsError(try SpiralSegment(start: .init(x: 0, y: 0), length: 100, startHeading: 0, startCurvature: 0, endCurvature: 0.001, tolerances: t))
    }
}
