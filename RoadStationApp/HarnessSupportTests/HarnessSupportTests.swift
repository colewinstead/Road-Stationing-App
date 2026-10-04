import XCTest
import RoadStationCore
import RoadStationHarnessSupport

final class HarnessSupportTests: XCTestCase {
    func testFieldCameraFollowBrowsingStalenessRecenterAndFit() throws {
        var camera = FieldCanvasCamera()
        let phone = ProjectCoordinate(x: 986327, y: 1453411)
        let nearest = ProjectCoordinate(x: 986327, y: 1453406)
        camera.follow(phone: phone, nearest: nearest, contextSpan: 50, isCurrent: true)
        let initial = try XCTUnwrap(camera.bounds)
        camera.magnify(2)
        camera.move(x: 75, y: -40)
        XCTAssertFalse(camera.isFollowing)
        camera.follow(phone: .init(x: phone.x + 10, y: phone.y), nearest: nearest, contextSpan: 50, isCurrent: true)
        XCTAssertEqual(camera.bounds?.minX, initial.minX, "Fresh GPS must not move a browsed camera")
        XCTAssertEqual(camera.pan, .init(x: 75, y: -40))
        camera.recenter(phone: phone, nearest: nearest, contextSpan: 50)
        XCTAssertFalse(camera.isFollowing, "Recenter is a one-shot action")
        XCTAssertEqual(camera.zoom, 1); XCTAssertEqual(camera.pan, .init(x: 0, y: 0))
        camera.resume(phone: phone, nearest: nearest, contextSpan: 50)
        camera.follow(phone: .init(x: phone.x + 10, y: phone.y), nearest: .init(x: nearest.x + 10, y: nearest.y), contextSpan: 50, isCurrent: false)
        XCTAssertEqual(camera.bounds?.minX, initial.minX, "Stale fixes must not drive Follow")
        camera.follow(phone: .init(x: phone.x + 10, y: phone.y), nearest: .init(x: nearest.x + 10, y: nearest.y), contextSpan: 50, isCurrent: true)
        XCTAssertEqual(try XCTUnwrap(camera.bounds).minX, initial.minX + 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(camera.bounds).maxX - camera.bounds!.minX, initial.maxX - initial.minX, accuracy: 1e-9)
        camera.resume(phone: .init(x: 0, y: 0), nearest: .init(x: 0, y: 0), contextSpan: 50)
        camera.follow(phone: .init(x: 100, y: 0), nearest: .init(x: 0, y: 0), contextSpan: 50, isCurrent: true)
        let widerViewport = CanvasViewport(bounds: try XCTUnwrap(camera.bounds), width: 390, height: 280)
        for point in [ProjectCoordinate(x: 0, y: 0), .init(x: 100, y: 0)] {
            let screen = widerViewport.screen(point)
            XCTAssertGreaterThanOrEqual(screen.x, 24); XCTAssertLessThanOrEqual(screen.x, 366)
        }
        let alignmentBounds = SegmentBounds(points: [.init(x: 0, y: 0), .init(x: 1000, y: 500)])
        camera.fitAlignment(alignmentBounds)
        XCTAssertFalse(camera.isFollowing)
        XCTAssertEqual(camera.bounds?.maxX, 1000, "Fit Alignment must not include a distant phone/query")
        camera.follow(phone: phone, nearest: nearest, contextSpan: 50, isCurrent: true)
        XCTAssertEqual(camera.bounds?.maxX, 1000)
    }
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
