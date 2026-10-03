import Foundation
import XCTest
@testable import RoadStationCore

enum TestSupport {
    static func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try Data(contentsOf: url)
    }
    static func alignment(_ name: String) throws -> Alignment {
        try LandXMLParser().parse(data: fixture(name)).alignments[0]
    }
    static func lineAlignment(start: ProjectCoordinate = .init(x: 0, y: 0), end: ProjectCoordinate = .init(x: 1000, y: 0),
                              startStation: Double = 10000, equations: [StationEquation] = []) throws -> Alignment {
        try Alignment(name: "Test", startStation: startStation,
            geometries: [.line(try LineSegment(start: start, end: end))], stationEquations: equations)
    }
    static func curve(clockwise: Bool = false, startAngle: Double = 0, sweep: Double = .pi / 2, radius: Double = 100) throws -> CircularCurveSegment {
        let sign = clockwise ? -1.0 : 1.0
        return try CircularCurveSegment(start: .init(x: radius * cos(startAngle), y: radius * sin(startAngle)),
            end: .init(x: radius * cos(startAngle + sign * sweep), y: radius * sin(startAngle + sign * sweep)),
            center: .init(x: 0, y: 0), rotation: clockwise ? .clockwise : .counterclockwise,
            radius: radius, declaredLength: radius * sweep)
    }
    static func spiral(decreasing: Bool = false, clockwise: Bool = false) throws -> SpiralSegment {
        let k = clockwise ? -0.005 : 0.005
        return try SpiralSegment(start: .init(x: 0, y: 0), length: 100, startHeading: 0,
            startCurvature: decreasing ? k : 0, endCurvature: decreasing ? 0 : k)
    }
    static func assertPoint(_ point: ProjectCoordinate, _ x: Double, _ y: Double, accuracy: Double = 1e-8,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: accuracy, file: file, line: line)
    }
}
