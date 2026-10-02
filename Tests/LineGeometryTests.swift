import XCTest
@testable import RoadStationCore

final class LineGeometryTests: XCTestCase {
    func testAnalyticProjection() throws {
        let line = try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))
        let result = try line.closestPoint(to: .init(x: 30, y: 12))
        XCTAssertEqual(result.distanceAlong, 30, accuracy: 1e-12)
        XCTAssertEqual(result.queryDistance, 12, accuracy: 1e-12)
    }
}
