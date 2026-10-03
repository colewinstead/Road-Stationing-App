import XCTest
@testable import RoadStationCore

final class AlignmentSamplingTests: XCTestCase {
    func testLineUsesOnlyEndpoints() throws {
        let a = try TestSupport.lineAlignment(); let p = try AlignmentSampling.polylines(alignment: a)
        XCTAssertEqual(p.count, 1); XCTAssertEqual(p[0].points.count, 2)
        TestSupport.assertPoint(p[0].points[1], 1000, 0)
    }
    func testCurvedDisplayChordError() throws {
        let a = try TestSupport.alignment("spiral-curve-spiral.xml")
        let paths = try AlignmentSampling.polylines(alignment: a, maximumChordError: 0.01)
        for path in paths {
            let segment = a.segments[path.segmentIndex]
            let count = path.points.count - 1
            for i in 0..<count {
                let mid = try segment.geometry.point(at: segment.length * (Double(i) + 0.5) / Double(count))
                let p = path.points[i]; let q = path.points[i + 1]
                let chordMid = ProjectCoordinate(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
                XCTAssertLessThanOrEqual(mid.distance(to: chordMid), 0.010000001)
            }
        }
    }
    func testDisconnectedSegmentsRemainSeparate() throws {
        let a = try Alignment(name: "Gap", geometries: [
            .line(LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0))),
            .line(LineSegment(start: .init(x: 200, y: 0), end: .init(x: 300, y: 0)))])
        let paths = try AlignmentSampling.polylines(alignment: a)
        XCTAssertEqual(paths.count, 2); XCTAssertEqual(paths[1].points[0].x - paths[0].points[1].x, 100)
    }
    func testInvalidDisplayToleranceRejected() throws {
        let a = try TestSupport.lineAlignment()
        XCTAssertThrowsError(try AlignmentSampling.polylines(alignment: a, maximumChordError: 0))
    }
}
