import XCTest
@testable import RoadStationCore

final class CurveGeometryTests: XCTestCase {
    func testCounterclockwiseQuarterCircle() throws {
        let c = try TestSupport.curve()
        TestSupport.assertPoint(try c.point(at: c.length / 2), 100 / sqrt(2), 100 / sqrt(2))
        XCTAssertEqual(c.tangent(at: 0).x, 0, accuracy: 1e-12); XCTAssertEqual(c.tangent(at: 0).y, 1, accuracy: 1e-12)
    }
    func testClockwiseQuarterCircle() throws {
        let c = try TestSupport.curve(clockwise: true)
        TestSupport.assertPoint(try c.point(at: c.length / 2), 100 / sqrt(2), -100 / sqrt(2))
        XCTAssertEqual(c.tangent(at: 0).y, -1, accuracy: 1e-12)
    }
    func testHalfCircle() throws {
        let c = try TestSupport.curve(sweep: .pi)
        TestSupport.assertPoint(try c.point(at: c.length / 2), 0, 100)
        XCTAssertEqual(c.length, 100 * .pi, accuracy: 1e-10)
    }
    func testMajorArc() throws {
        let c = try TestSupport.curve(sweep: 1.5 * .pi)
        let p = try c.closestPoint(to: .init(x: -150, y: 0))
        TestSupport.assertPoint(p.point, -100, 0); XCTAssertEqual(p.distanceAlong, 100 * .pi, accuracy: 1e-9)
    }
    func testCrossesZero() throws {
        let c = try TestSupport.curve(startAngle: 350 * .pi / 180, sweep: 20 * .pi / 180)
        let p = try c.closestPoint(to: .init(x: 125, y: 0))
        TestSupport.assertPoint(p.point, 100, 0); XCTAssertEqual(p.distanceAlong, c.length / 2, accuracy: 1e-9)
    }
    func testOnArc() throws {
        let c = try TestSupport.curve(); let p = try c.closestPoint(to: .init(x: 60, y: 80))
        XCTAssertEqual(p.queryDistance, 0, accuracy: 1e-10); XCTAssertEqual(p.distanceAlong, atan2(80, 60) * 100, accuracy: 1e-10)
    }
    func testInsideRadius() throws {
        let c = try TestSupport.curve(); let p = try c.closestPoint(to: .init(x: 30, y: 40))
        TestSupport.assertPoint(p.point, 60, 80); XCTAssertEqual(p.queryDistance, 50, accuracy: 1e-10)
    }
    func testOutsideRadius() throws {
        let c = try TestSupport.curve(); let p = try c.closestPoint(to: .init(x: 90, y: 120))
        TestSupport.assertPoint(p.point, 60, 80); XCTAssertEqual(p.queryDistance, 50, accuracy: 1e-10)
    }
    func testNearPC() throws {
        let c = try TestSupport.curve(); let p = try c.closestPoint(to: .init(x: 100, y: -1))
        XCTAssertEqual(p.distanceAlong, 0, accuracy: 1e-12)
    }
    func testNearPT() throws {
        let c = try TestSupport.curve(); let p = try c.closestPoint(to: .init(x: -1, y: 100))
        XCTAssertEqual(p.distanceAlong, c.length, accuracy: 1e-12)
    }
    func testCenterIsAmbiguous() throws {
        XCTAssertTrue(try TestSupport.curve().closestPoint(to: .init(x: 0, y: 0)).ambiguous)
    }
    func testFullCircle() throws {
        let c = try TestSupport.curve(sweep: 2 * .pi)
        XCTAssertEqual(c.length, 200 * .pi, accuracy: 1e-10)
        XCTAssertTrue(try c.closestPoint(to: c.start).ambiguous)
    }
    func testInconsistentRadiusAndLengthRejected() throws {
        XCTAssertThrowsError(try CircularCurveSegment(start: .init(x: 10, y: 0), end: .init(x: 0, y: 11), center: .init(x: 0, y: 0), rotation: .counterclockwise))
        XCTAssertThrowsError(try CircularCurveSegment(start: .init(x: 10, y: 0), end: .init(x: 0, y: 10), center: .init(x: 0, y: 0), rotation: .clockwise, declaredLength: 5 * .pi))
    }
}
