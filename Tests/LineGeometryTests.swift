import XCTest
@testable import RoadStationCore

final class LineGeometryTests: XCTestCase {
    func testAnalyticProjection() throws {
        let line = try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))
        let result = try line.closestPoint(to: .init(x: 30, y: 12))
        XCTAssertEqual(result.distanceAlong, 30, accuracy: 1e-12)
        XCTAssertEqual(result.queryDistance, 12, accuracy: 1e-12)
    }
    func testVerticalLine() throws {
        let line = try LineSegment(start: .init(x: 5, y: 10), end: .init(x: 5, y: 110))
        let p = try line.closestPoint(to: .init(x: -5, y: 60))
        TestSupport.assertPoint(p.point, 5, 60); XCTAssertEqual(p.distanceAlong, 50, accuracy: 1e-12)
        XCTAssertEqual(p.tangent.bearing, 0, accuracy: 1e-12)
    }
    func testDiagonalLine() throws {
        let line = try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 100))
        let p = try line.closestPoint(to: .init(x: 40, y: 60))
        TestSupport.assertPoint(p.point, 50, 50); XCTAssertEqual(p.distanceAlong, sqrt(5000), accuracy: 1e-10)
    }
    func testOnLine() throws {
        let r = try AlignmentEngine(alignment: TestSupport.lineAlignment()).stationOffset(point: .init(x: 25, y: 0))
        XCTAssertEqual(r.side, .onAlignment); XCTAssertEqual(r.signedOffset, 0, accuracy: 1e-12)
    }
    func testBeforeStartClamped() throws {
        let r = try AlignmentEngine(alignment: TestSupport.lineAlignment()).stationOffset(point: .init(x: -20, y: 5))
        XCTAssertEqual(r.geometricDistance, 0, accuracy: 1e-12); XCTAssertEqual(r.longitudinalResidual, -20, accuracy: 1e-12)
        XCTAssertEqual(r.distanceFromQueryPointToAlignment, hypot(20, 5), accuracy: 1e-12)
    }
    func testAfterEndClamped() throws {
        let r = try AlignmentEngine(alignment: TestSupport.lineAlignment()).stationOffset(point: .init(x: 1020, y: -5))
        XCTAssertEqual(r.geometricDistance, 1000, accuracy: 1e-12); XCTAssertEqual(r.longitudinalResidual, 20, accuracy: 1e-12)
        XCTAssertEqual(r.signedOffset, -5, accuracy: 1e-12)
    }
    func testPointAtDistanceAndElevation() throws {
        let line = try LineSegment(start: .init(x: 0, y: 0, z: 10), end: .init(x: 100, y: 0, z: 30))
        let p = try line.point(at: 25); TestSupport.assertPoint(p, 25, 0); XCTAssertEqual(p.z!, 15, accuracy: 1e-12)
        XCTAssertEqual(line.length, 100, accuracy: 1e-12)
    }
    func testInvalidLine() {
        XCTAssertThrowsError(try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 0, y: 0)))
        XCTAssertThrowsError(try LineSegment(start: .init(x: .nan, y: 0), end: .init(x: 10, y: 0)))
    }
    func testOutOfRangeDistance() throws {
        let line = try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))
        XCTAssertThrowsError(try line.point(at: -1)); XCTAssertThrowsError(try line.point(at: 101))
    }
}
