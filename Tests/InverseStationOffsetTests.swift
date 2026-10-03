import XCTest
@testable import RoadStationCore

final class InverseStationOffsetTests: XCTestCase {
    func testLineInverse() throws {
        let e = try AlignmentEngine(alignment: TestSupport.lineAlignment())
        TestSupport.assertPoint(try e.coordinate(station: 10250, offset: 25).coordinate, 250, 25)
        TestSupport.assertPoint(try e.coordinate(station: 10250, offset: -25).coordinate, 250, -25)
    }
    func testCurveInverse() throws {
        let a = try Alignment(name: "Curve", geometries: [.circularCurve(TestSupport.curve())])
        TestSupport.assertPoint(try AlignmentEngine(alignment: a).coordinate(station: 100 * atan2(80, 60), offset: 50).coordinate, 30, 40)
    }
    func testSpiralInverse() throws {
        let s = try TestSupport.spiral(); let a = try Alignment(name: "Spiral", geometries: [.spiral(s)])
        let p = try AlignmentEngine(alignment: a).coordinate(station: 50, offset: 10).coordinate
        TestSupport.assertPoint(p, 49.980472281808716 - sin(0.0625) * 10, 1.0413760591870398 + cos(0.0625) * 10)
    }
    func testEquationInverse() throws {
        let a = try TestSupport.lineAlignment(equations: [.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        TestSupport.assertPoint(try AlignmentEngine(alignment: a).coordinate(station: 10250, offset: 10).coordinate, 150, 10)
    }
    func testAmbiguousInverseRequiresBranch() throws {
        let a = try TestSupport.lineAlignment(equations: [.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10050)])
        let e = AlignmentEngine(alignment: a)
        XCTAssertThrowsError(try e.coordinate(station: 10075, offset: 10))
        TestSupport.assertPoint(try e.coordinate(station: 10075, offset: 10, branchIndex: 0).coordinate, 75, 10)
        TestSupport.assertPoint(try e.coordinate(station: 10075, offset: 10, branchIndex: 1).coordinate, 125, 10)
    }
    func testEquationGapRejected() throws {
        let a = try TestSupport.lineAlignment(equations: [.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        XCTAssertThrowsError(try AlignmentEngine(alignment: a).coordinate(station: 10150, offset: 0))
    }
    func testEndpointInverse() throws {
        let e = try AlignmentEngine(alignment: TestSupport.lineAlignment())
        TestSupport.assertPoint(try e.coordinate(station: 10000, offset: 5).coordinate, 0, 5)
        TestSupport.assertPoint(try e.coordinate(station: 11000, offset: 5).coordinate, 1000, 5)
    }
    func testNonFiniteOffsetRejected() throws {
        let e = try AlignmentEngine(alignment: TestSupport.lineAlignment())
        XCTAssertThrowsError(try e.coordinate(station: 10100, offset: .infinity))
    }
}
