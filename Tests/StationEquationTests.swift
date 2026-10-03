import XCTest
@testable import RoadStationCore

final class StationEquationTests: XCTestCase {
    private func engine(_ equations: [StationEquation]) throws -> StationingEngine {
        try StationingEngine(alignment: TestSupport.lineAlignment(equations: equations))
    }
    func testNoEquation() throws {
        let s = try engine([]); XCTAssertEqual(try s.station(at: 123), 10123, accuracy: 1e-12)
        XCTAssertEqual(try s.location(station: 10123).geometricDistance, 123, accuracy: 1e-12)
    }
    func testAheadEquation() throws {
        let s = try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        XCTAssertEqual(try s.station(at: 150), 10250, accuracy: 1e-12)
        XCTAssertEqual(s.resolve(station: 10150), .outsideAlignment)
    }
    func testBackEquationAmbiguity() throws {
        let s = try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10050)])
        guard case .ambiguous(let c) = s.resolve(station: 10075) else { return XCTFail("Expected ambiguity") }
        XCTAssertEqual(c.map(\.geometricDistance), [75, 125])
        XCTAssertThrowsError(try s.location(station: 10075))
        XCTAssertEqual(try s.location(station: 10075, branchIndex: 1).geometricDistance, 125, accuracy: 1e-12)
    }
    func testExactlyAtEquation() throws {
        let s = try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        XCTAssertEqual(try s.station(at: 100), 10200, accuracy: 1e-12)
        XCTAssertEqual(try s.station(at: 100, equationSide: .back), 10100, accuracy: 1e-12)
        XCTAssertEqual(try s.location(station: 10100).equationSide, .back)
        XCTAssertEqual(try s.location(station: 10200).equationSide, .ahead)
    }
    func testImmediatelyBeforeAndAfter() throws {
        let s = try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        XCTAssertEqual(try s.station(at: 100 - 1e-8), 10100 - 1e-8, accuracy: 1e-10)
        XCTAssertEqual(try s.station(at: 100 + 1e-8), 10200 + 1e-8, accuracy: 1e-10)
    }
    func testMultipleEquations() throws {
        let s = try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200),
                            .init(geometricDistance: 300, stationBack: 10400, stationAhead: 10300)])
        XCTAssertEqual(try s.station(at: 400), 10400, accuracy: 1e-12)
        guard case .ambiguous(let c) = s.resolve(station: 10350) else { return XCTFail("Expected overlap") }
        XCTAssertEqual(c.map(\.geometricDistance), [250, 350])
    }
    func testInvalidEquationsRejected() {
        XCTAssertThrowsError(try engine([.init(geometricDistance: 100, stationBack: 99, stationAhead: 10200)]))
        XCTAssertThrowsError(try engine([.init(geometricDistance: 1100, stationBack: 11100, stationAhead: 11200)]))
        XCTAssertThrowsError(try engine([.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200),
                                        .init(geometricDistance: 100, stationBack: 10200, stationAhead: 10300)]))
    }
    func testOutsideAndNonFiniteStations() throws {
        let s = try engine([])
        XCTAssertEqual(s.resolve(station: 9999), .outsideAlignment); XCTAssertEqual(s.resolve(station: .nan), .outsideAlignment)
        XCTAssertThrowsError(try s.station(at: 1001)); XCTAssertThrowsError(try s.station(at: .infinity))
    }
    func testFormatting() throws {
        XCTAssertEqual(StationFormatter.string(42738.42), "427+38.42")
        XCTAssertEqual(StationFormatter.string(125), "1+25.00"); XCTAssertEqual(StationFormatter.string(0), "0+00.00")
        XCTAssertEqual(StationFormatter.string(199.999), "2+00.00")
        XCTAssertEqual(StationFormatter.string(-25.4, precision: 1), "-0+25.4")
        XCTAssertEqual(try StationFormatter.parse("427+38.42"), 42738.42, accuracy: 1e-10)
        XCTAssertEqual(try StationFormatter.parse("-0+25.4"), -25.4, accuracy: 1e-12)
        XCTAssertThrowsError(try StationFormatter.parse("1+125")); XCTAssertThrowsError(try StationFormatter.parse("nan"))
    }
}
