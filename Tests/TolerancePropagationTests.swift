import Foundation
import XCTest
@testable import RoadStationCore

final class TolerancePropagationTests: XCTestCase {
    private func line(_ tolerances: GeometryTolerances = .standard, y: Double = 0) throws -> LineSegment {
        try LineSegment(start: .init(x: 0, y: y), end: .init(x: 100, y: y), tolerances: tolerances)
    }
    func testNearZeroLineValidationUsesConfiguredCoordinateTolerance() throws {
        var loose = GeometryTolerances(); loose.coordinate = 0.01
        XCTAssertThrowsError(try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 0.001, y: 0), tolerances: loose))
        var tight = GeometryTolerances(); tight.coordinate = 1e-10
        XCTAssertNoThrow(try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 1e-8, y: 0), tolerances: tight))
        XCTAssertThrowsError(try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 0, y: 0), tolerances: tight))
    }
    func testParserPropagatesToleranceToLineAndAlignmentQueries() throws {
        let xml = Data("<LandXML><Units><Metric linearUnit=\"meter\"/></Units><Alignments><Alignment name=\"tiny\"><CoordGeom><Line><Start>0 0</Start><End>0 0.00000001</End></Line></CoordGeom></Alignment></Alignments></LandXML>".utf8)
        XCTAssertThrowsError(try LandXMLParser().parse(data: xml))
        var options = LandXMLParserOptions(); options.tolerances.coordinate = 1e-10; options.tolerances.station = 1e-12
        let a = try LandXMLParser(options: options).parse(data: xml).alignments[0]
        XCTAssertEqual(a.tolerances, options.tolerances)
        XCTAssertEqual(a.segments[0].geometry.tolerances, options.tolerances)
        XCTAssertEqual(try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 5e-9, y: 1e-9)).side, .left)
        XCTAssertThrowsError(try AlignmentEngine(alignment: a).point(at: -1e-10))
        options.tolerances.coordinate = 0.01
        XCTAssertThrowsError(try LandXMLParser(options: options).parse(data: xml))
    }
    func testStationBoundaryToleranceOnEveryGeometryAndEngine() throws {
        var t = GeometryTolerances(); t.station = 0.01
        let l = try line(t)
        let c = try CircularCurveSegment(start: .init(x: 100, y: 0), end: .init(x: 0, y: 100),
            center: .init(x: 0, y: 0), rotation: .counterclockwise, tolerances: t)
        let s = try SpiralSegment(start: .init(x: 0, y: 0), length: 100, startHeading: 0,
            startCurvature: 0, endCurvature: 0.005, tolerances: t)
        for g in [SegmentGeometry.line(l), .circularCurve(c), .spiral(s)] {
            XCTAssertEqual(try g.point(at: -0.005).x, try g.point(at: 0).x, accuracy: 1e-12)
            XCTAssertEqual(try g.point(at: g.length + 0.005).y, try g.point(at: g.length).y, accuracy: 1e-12)
            XCTAssertThrowsError(try g.point(at: -0.02))
            let a = try Alignment(name: "boundary", geometries: [g])
            XCTAssertNoThrow(try AlignmentEngine(alignment: a).point(at: -0.005))
            XCTAssertEqual(try StationingEngine(alignment: a).station(at: g.length + 0.005), g.length, accuracy: 1e-12)
        }
        t.station = 1e-10
        let a = try Alignment(name: "tight", geometries: [.line(line())], tolerances: t)
        XCTAssertThrowsError(try AlignmentEngine(alignment: a).point(at: -1e-8))
        XCTAssertThrowsError(try StationingEngine(alignment: a).station(at: -1e-8))
    }
    func testOnAlignmentClassificationUsesAlignmentContext() throws {
        var t = GeometryTolerances(); t.coordinate = 0.01
        let a = try Alignment(name: "loose", geometries: [.line(line())], tolerances: t)
        XCTAssertEqual(try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 50, y: 0.005)).side, .onAlignment)
        XCTAssertEqual(try AlignmentEngine(alignment: a).stationOffset(point: .init(x: 50, y: -0.02)).side, .right)
        XCTAssertEqual(try AlignmentEngine(alignment: Alignment(name: "standard", geometries: [.line(line())]))
            .stationOffset(point: .init(x: 50, y: 0.005)).side, .left)
    }
    func testTieToleranceControlsAmbiguityIncludingBoundsPruning() throws {
        var t = GeometryTolerances(); t.tieDistance = 0.02
        let geometries: [SegmentGeometry] = [.line(try line()), .line(try line(y: 2.01))]
        let query = ProjectCoordinate(x: 50, y: 1)
        let custom = try Alignment(name: "ties", geometries: geometries, tolerances: t)
        XCTAssertTrue(try AlignmentEngine(alignment: custom).stationOffset(point: query).nearestLocationIsAmbiguous)
        let standard = try Alignment(name: "ties", geometries: geometries)
        XCTAssertFalse(try AlignmentEngine(alignment: standard).stationOffset(point: query).nearestLocationIsAmbiguous)
    }
    func testTangentAmbiguityUsesConfiguredThreshold() throws {
        let first = try LineSegment(start: .init(x: -100, y: 0), end: .init(x: 0, y: 0))
        let second = try LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0.001))
        let geometries: [SegmentGeometry] = [.line(first), .line(second)]
        var t = GeometryTolerances(); t.tangentAmbiguity = 0.001
        let custom = try Alignment(name: "corner", geometries: geometries, tolerances: t)
        XCTAssertFalse(try AlignmentEngine(alignment: custom).stationOffset(point: .init(x: 0, y: 0)).nearestLocationIsAmbiguous)
        let standard = try Alignment(name: "corner", geometries: geometries)
        XCTAssertTrue(try AlignmentEngine(alignment: standard).stationOffset(point: .init(x: 0, y: 0)).nearestLocationIsAmbiguous)
    }
    func testCurveCenterAmbiguityAndBoundsUseStoredTolerance() throws {
        var t = GeometryTolerances(); t.coordinate = 0.01
        let c = try CircularCurveSegment(start: .init(x: 100, y: 0), end: .init(x: 0, y: 100),
            center: .init(x: 0, y: 0), rotation: .counterclockwise, tolerances: t)
        let query = ProjectCoordinate(x: 0.005 / sqrt(2), y: 0.005 / sqrt(2))
        XCTAssertTrue(try c.closestPoint(to: query).ambiguous)
        XCTAssertFalse(try TestSupport.curve().closestPoint(to: query).ambiguous)
        XCTAssertEqual(c.bounds.maxX, 100.01, accuracy: 1e-12)
        XCTAssertEqual(c.bounds.minY, -0.01, accuracy: 1e-12)
    }
    func testCurveEndpointTieUsesStoredTolerance() throws {
        var t = GeometryTolerances(); t.tieDistance = 0.1
        let custom = try CircularCurveSegment(start: .init(x: 100, y: 0), end: .init(x: 0, y: 100),
            center: .init(x: 0, y: 0), rotation: .counterclockwise, tolerances: t)
        let query = ProjectCoordinate(x: -10, y: -10.01)
        XCTAssertTrue(try custom.closestPoint(to: query).ambiguous)
        XCTAssertFalse(try TestSupport.curve().closestPoint(to: query).ambiguous)
    }
    func testResolutionDeduplicationUsesCustomStationToleranceWithoutSwallowingGaps() throws {
        var t = GeometryTolerances(); t.station = 0.1
        let equation = StationEquation(geometricDistance: 50, stationBack: 50, stationAhead: 49.98)
        let a = try Alignment(name: "overlap", geometries: [.line(line())], stationEquations: [equation], tolerances: t)
        let engine = StationingEngine(alignment: a)
        guard case .unique = engine.resolve(station: 49.99) else { return XCTFail("Expected deduplication") }
        XCTAssertEqual(try engine.location(station: 49.99, branchIndex: 1).geometricDistance, 50.01, accuracy: 1e-12)
        let standard = try Alignment(name: "overlap", geometries: [.line(line())], stationEquations: [equation])
        guard case .ambiguous = StationingEngine(alignment: standard).resolve(station: 49.99) else { return XCTFail("Expected distinct locations") }
        let gap = try Alignment(name: "gap", geometries: [.line(line())],
            stationEquations: [.init(geometricDistance: 50, stationBack: 50, stationAhead: 50.05)], tolerances: t)
        XCTAssertEqual(StationingEngine(alignment: gap).resolve(station: 50.025), .outsideAlignment)
    }
    func testAlignmentInheritsContextAndExplicitOverrideRebuildsAllSegments() throws {
        var t = GeometryTolerances(); t.station = 0.01; t.coordinate = 0.001
        let l = try line(t)
        let inherited = try Alignment(name: "inherited", geometries: [.line(l)])
        XCTAssertEqual(inherited.tolerances, t)
        XCTAssertThrowsError(try Alignment(name: "mixed", geometries: [.line(l), .line(line())]))
        let s = try TestSupport.spiral(); let c = try TestSupport.curve()
        let overridden = try Alignment(name: "override", geometries: [.line(line()), .circularCurve(c), .spiral(s)], tolerances: t)
        XCTAssertTrue(overridden.segments.allSatisfy { $0.geometry.tolerances == t })
        for segment in overridden.segments { XCTAssertNoThrow(try segment.geometry.point(at: -0.005)) }
    }
    func testInvalidToleranceRejectedByLineAndAlignment() throws {
        var t = GeometryTolerances(); t.station = .nan
        XCTAssertThrowsError(try line(t))
        XCTAssertThrowsError(try Alignment(name: "invalid", geometries: [.line(line())], tolerances: t))
    }
}
