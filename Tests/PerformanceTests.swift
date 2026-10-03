import Foundation
import XCTest
@testable import RoadStationCore

final class PerformanceTests: XCTestCase {
    func testHundredsOfMixedSegmentsThousandsOfQueries() throws {
        var geometries: [SegmentGeometry] = []
        var start = ProjectCoordinate(x: 2456789, y: 987654); var heading = 0.0
        for i in 0..<75 {
            let sign = i % 2 == 0 ? 1.0 : -1.0
            let entry = try SpiralSegment(start: start, length: 20, startHeading: heading, startCurvature: 0, endCurvature: sign / 500)
            geometries.append(.spiral(entry)); start = entry.end; heading = entry.heading(at: 20)
            let center = OffsetEngine.coordinate(centerline: start, tangent: entry.tangent(at: 20), offset: sign * 500)
            let radial = GeometryUtilities.displacement(from: center, to: start)
            let a = atan2(radial.y, radial.x) + sign * 0.04
            let end = ProjectCoordinate(x: center.x + 500 * cos(a), y: center.y + 500 * sin(a))
            let curve = try CircularCurveSegment(start: start, end: end, center: center, rotation: sign > 0 ? .counterclockwise : .clockwise, radius: 500, declaredLength: 20)
            geometries.append(.circularCurve(curve)); start = end; heading += sign * 0.04
            let exit = try SpiralSegment(start: start, length: 20, startHeading: heading, startCurvature: sign / 500, endCurvature: 0)
            geometries.append(.spiral(exit)); start = exit.end; heading = exit.heading(at: 20)
            let line = try LineSegment(start: start, end: GeometryUtilities.translated(start, by: exit.tangent(at: 20), scale: 20))
            geometries.append(.line(line)); start = line.end
        }
        let a = try Alignment(name: "Mixed road", geometries: geometries); let e = AlignmentEngine(alignment: a)
        let clock = Date()
        for i in 0..<1000 {
            let d = Double((i * 137) % 5990) + 0.25
            let p = try e.coordinate(station: d, offset: -5)
            let r = try e.stationOffset(point: p.coordinate)
            XCTAssertEqual(r.geometricDistance, d, accuracy: 2e-6); XCTAssertEqual(r.signedOffset, -5, accuracy: 2e-6)
            XCTAssertFalse(r.nearestLocationIsAmbiguous)
        }
        print("Performance: 300 mixed segments / 1000 inverse+forward queries: \(Date().timeIntervalSince(clock)) seconds")
    }
    func testHundredsOfSegmentsThousandsOfQueries() throws {
        var geometries: [SegmentGeometry] = []
        for i in 0..<300 {
            geometries.append(.line(try LineSegment(start: .init(x: Double(i) * 100, y: 0), end: .init(x: Double(i + 1) * 100, y: 0))))
        }
        let a = try Alignment(name: "Long road", geometries: geometries); let e = AlignmentEngine(alignment: a)
        let start = Date()
        for i in 0..<2000 {
            let x = Double((i * 137) % 29999) + 0.25
            let r = try e.stationOffset(point: .init(x: x, y: -10))
            XCTAssertEqual(r.geometricDistance, x, accuracy: 1e-8); XCTAssertEqual(r.signedOffset, -10, accuracy: 1e-8)
        }
        // Record time without imposing a machine-dependent timing assertion.
        print("Performance: 300 segments / 2000 exact queries: \(Date().timeIntervalSince(start)) seconds")
    }
}
