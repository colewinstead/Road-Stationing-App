import XCTest
@testable import RoadStationCore

final class StationOffsetTests: XCTestCase {
    private func checkDirection(_ end: ProjectCoordinate, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try TestSupport.lineAlignment(end: end); let e = AlignmentEngine(alignment: a)
        let center = try e.point(at: a.totalGeometricLength / 2)
        for offset in [-25.0, 0, 25] {
            let q = OffsetEngine.coordinate(centerline: center.point, tangent: center.tangent, offset: offset)
            let r = try e.stationOffset(point: q)
            XCTAssertEqual(r.signedOffset, offset, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(r.side, offset > 0 ? .left : (offset < 0 ? .right : .onAlignment), file: file, line: line)
            XCTAssertEqual(r.geometricDistance, a.totalGeometricLength / 2, accuracy: 1e-9, file: file, line: line)
        }
    }
    func testEastLT_RT() throws { try checkDirection(.init(x: 100, y: 0)) }
    func testWestLT_RT() throws { try checkDirection(.init(x: -100, y: 0)) }
    func testNorthLT_RT() throws { try checkDirection(.init(x: 0, y: 100)) }
    func testSouthLT_RT() throws { try checkDirection(.init(x: 0, y: -100)) }
    func testNortheastLT_RT() throws { try checkDirection(.init(x: 100, y: 100)) }
    func testSouthwestLT_RT() throws { try checkDirection(.init(x: -100, y: -100)) }
    func testCurveLeftIsInsideCCW() throws {
        let a = try Alignment(name: "Curve", geometries: [.circularCurve(TestSupport.curve())])
        let r = try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 30, y: 40))
        XCTAssertEqual(r.signedOffset, 50, accuracy: 1e-10); XCTAssertEqual(r.side, .left)
        XCTAssertEqual(r.geometricDistance, atan2(40, 30) * 100, accuracy: 1e-10)
    }
    func testCurveRightIsInsideCW() throws {
        let a = try Alignment(name: "Curve", geometries: [.circularCurve(TestSupport.curve(clockwise: true))])
        let r = try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 30, y: -40))
        XCTAssertEqual(r.signedOffset, -50, accuracy: 1e-10); XCTAssertEqual(r.side, .right)
    }
    func testGlobalNearestSegment() throws {
        let a = try TestSupport.alignment("tangent-curve-tangent.xml")
        let r = try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 220, y: 150))
        XCTAssertEqual(r.nearestSegmentIndex, 2); XCTAssertEqual(r.segmentType, "Line")
        XCTAssertEqual(r.signedOffset, -20, accuracy: 1e-9)
        XCTAssertEqual(r.geometricDistance, 150 + 50 * .pi, accuracy: 1e-9)
    }
    func testEqualDistanceDistinctLocationsMarkedAmbiguous() throws {
        let a = try Alignment(name: "Parallel", geometries: [
            .line(LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))),
            .line(LineSegment(start: .init(x: 100, y: 10), end: .init(x: 0, y: 10)))])
        let r = try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 50, y: 5))
        XCTAssertTrue(r.nearestLocationIsAmbiguous)
    }
    func testCornerTangentAmbiguity() throws {
        let a = try Alignment(name: "Corner", geometries: [
            .line(LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))),
            .line(LineSegment(start: .init(x: 100, y: 0), end: .init(x: 100, y: 100)))])
        XCTAssertTrue(try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 100, y: 0)).nearestLocationIsAmbiguous)
    }
    func testLargeProjectedCoordinates() throws {
        let a = try TestSupport.lineAlignment(start: .init(x: 2456789.123, y: 987654.321), end: .init(x: 2457789.123, y: 987654.321))
        let r = try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 2457039.123, y: 987629.321))
        XCTAssertEqual(r.geometricDistance, 250, accuracy: 1e-8); XCTAssertEqual(r.signedOffset, -25, accuracy: 1e-8)
    }
    func testNonFinitePointRejected() throws {
        let e = try AlignmentEngine(alignment: TestSupport.lineAlignment())
        XCTAssertThrowsError(try e.stationOffset(point: .init(x: .nan, y: 5)))
    }
}
