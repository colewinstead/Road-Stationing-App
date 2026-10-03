import XCTest
import RoadStationCore
import RoadStationHarnessSupport

final class HarnessSupportTests: XCTestCase {
    func testLargeProjectedCoordinatesRoundTripAfterPanAndZoom() {
        let bounds = SegmentBounds(points: [.init(x: 986327.5959036754, y: 1453411.9250950934),
                                           .init(x: 1000744.5894447418, y: 1446675.9547965613)])
        let view = CanvasViewport(bounds: bounds, width: 390, height: 300, zoom: 4.2, pan: .init(x: 73, y: -31))
        let original = ProjectCoordinate(x: 995123.456789, y: 1450123.123456)
        let recovered = view.coordinate(view.screen(original))
        XCTAssertEqual(recovered.x, original.x, accuracy: 1e-9)
        XCTAssertEqual(recovered.y, original.y, accuracy: 1e-9)
    }
    func testNorthUpAspectRatioAndFit() {
        let view = CanvasViewport(bounds: .init(points: [.init(x: 0, y: 0), .init(x: 200, y: 100)]), width: 400, height: 300)
        let origin = view.screen(.init(x: 0, y: 0))
        let east = view.screen(.init(x: 10, y: 0)); let north = view.screen(.init(x: 0, y: 10))
        XCTAssertEqual(east.x - origin.x, origin.y - north.y, accuracy: 1e-12)
        XCTAssertGreaterThan(east.x, origin.x); XCTAssertLessThan(north.y, origin.y)
        XCTAssertGreaterThanOrEqual(origin.x, 24)
        XCTAssertLessThanOrEqual(view.screen(.init(x: 200, y: 100)).x, 376)
    }
    func testHorizontalAndVerticalFitsRemainInvertible() {
        for end in [ProjectCoordinate(x: 1000, y: 0), .init(x: 0, y: 1000), .init(x: 0, y: 0)] {
            let v = CanvasViewport(bounds: .init(points: [.init(x: 0, y: 0), end]), width: 320, height: 280)
            XCTAssertTrue(v.scale.isFinite); XCTAssertGreaterThan(v.scale, 0)
            XCTAssertEqual(v.coordinate(v.screen(end)).x, end.x, accuracy: 1e-9)
            XCTAssertEqual(v.coordinate(v.screen(end)).y, end.y, accuracy: 1e-9)
        }
        XCTAssertEqual(CanvasViewport.clampedZoom(.infinity), 1)
        XCTAssertEqual(CanvasViewport.clampedZoom(10000), 1000)
    }
    func testCoordinateEntryPreservesEastingNorthingAndRejectsNonfinite() throws {
        let p = try ManualQuery.coordinate(easting: " 986327.123456 ", northing: "1453411.654321")
        XCTAssertEqual(p.x, 986327.123456); XCTAssertEqual(p.y, 1453411.654321)
        XCTAssertThrowsError(try ManualQuery.coordinate(easting: "nan", northing: "2"))
        XCTAssertThrowsError(try ManualQuery.coordinate(easting: "1,000", northing: "2"))
    }
    func testStationAndOffsetEntryUseCoreConventions() throws {
        XCTAssertEqual(try ManualQuery.station("427+38.42"), 42738.42, accuracy: 1e-10)
        XCTAssertEqual(try ManualQuery.station("42738.42"), 42738.42, accuracy: 1e-10)
        XCTAssertEqual(try ManualQuery.signedOffset(magnitude: "32.6", side: .LT), 32.6)
        XCTAssertEqual(try ManualQuery.signedOffset(magnitude: "32.6", side: .RT), -32.6)
        XCTAssertEqual(try ManualQuery.signedOffset(magnitude: "0", side: .ON), 0)
        XCTAssertThrowsError(try ManualQuery.signedOffset(magnitude: "-5", side: .RT))
        XCTAssertThrowsError(try ManualQuery.signedOffset(magnitude: "5", side: .ON))
    }
    func testManualInverseRemainsAmbiguousUntilBranchIsChosen() throws {
        let a = try Alignment(name: "equation", geometries: [.line(LineSegment(start: .init(x: 0, y: 0), end: .init(x: 200, y: 0)))],
            stationEquations: [.init(geometricDistance: 100, stationBack: 100, stationAhead: 50)])
        let station = try ManualQuery.station("0+75")
        let offset = try ManualQuery.signedOffset(magnitude: "5", side: .RT)
        XCTAssertThrowsError(try AlignmentEngine(alignment: a).coordinate(station: station, offset: offset))
        let result = try AlignmentEngine(alignment: a).coordinate(station: station, offset: offset, branchIndex: 1)
        XCTAssertEqual(result.coordinate, .init(x: 125, y: -5))
    }
}
