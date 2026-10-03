import Foundation
import XCTest
@testable import RoadStationCore

final class LandXMLParserTests: XCTestCase {
    private func parse(_ content: String) throws -> Project { try LandXMLParser().parse(data: Data(content.utf8)) }
    func testExplicitNorthingEastingConversion() throws {
        let p = try LandXMLParser.coordinate(from: "987654.321 2456789.123 55.4")
        TestSupport.assertPoint(p, 2456789.123, 987654.321); XCTAssertEqual(p.z!, 55.4, accuracy: 1e-12)
        let flat = try LandXMLParser.coordinate(from: "10\n20"); TestSupport.assertPoint(flat, 20, 10); XCTAssertNil(flat.z)
    }
    func testBadCoordinates() {
        for value in ["", "1", "1 2 3 4", "NaN 10", "10 INF", "north east"] { XCTAssertThrowsError(try LandXMLParser.coordinate(from: value)) }
    }
    func testTangentAndMetadata() throws {
        let p = try LandXMLParser().parse(data: TestSupport.fixture("tangent-only.xml"))
        XCTAssertEqual(p.unit, .usSurveyFoot); XCTAssertEqual(p.name, "Tangent test")
        let a = p.alignments[0]; XCTAssertEqual(a.name, "TANGENT"); XCTAssertEqual(a.metadata.sourceIdentifier, "A1")
        XCTAssertEqual(a.metadata.description, "Eastbound tangent"); XCTAssertEqual(a.startStation, 10000)
        TestSupport.assertPoint(a.segments[0].start, 1000, 2000); XCTAssertEqual(a.totalGeometricLength, 1000)
    }
    func testCircularCurve() throws {
        let a = try TestSupport.alignment("simple-curve.xml")
        XCTAssertEqual(a.totalGeometricLength, 50 * .pi, accuracy: 1e-9)
        guard case .circularCurve(let c) = a.segments[0].geometry else { return XCTFail("Expected curve") }
        XCTAssertEqual(c.rotation, .counterclockwise); TestSupport.assertPoint(c.center, 0, 0)
    }
    func testTangentCurveTangentCumulativeDistances() throws {
        let a = try TestSupport.alignment("tangent-curve-tangent.xml")
        XCTAssertEqual(a.segments.count, 3); XCTAssertTrue(a.warnings.isEmpty)
        XCTAssertEqual(a.segments[1].geometricStartDistance, 100, accuracy: 1e-12)
        XCTAssertEqual(a.segments[2].geometricStartDistance, 100 + 50 * .pi, accuracy: 1e-9)
    }
    func testSpiralCurveSpiral() throws {
        let a = try TestSupport.alignment("spiral-curve-spiral.xml")
        XCTAssertEqual(a.segments.count, 5); XCTAssertEqual(a.totalGeometricLength, 500, accuracy: 1e-9)
        XCTAssertTrue(a.warnings.isEmpty)
        for i in 0..<4 {
            XCTAssertLessThan(a.segments[i].end.distance(to: a.segments[i + 1].start), 1e-9)
            let t0 = a.segments[i].geometry.tangent(at: a.segments[i].length)
            let t1 = a.segments[i + 1].geometry.tangent(at: 0)
            XCTAssertEqual(t0.dot(t1), 1, accuracy: 1e-10)
        }
    }
    func testPIOnlySpiral() throws {
        let data = try TestSupport.fixture("spiral-curve-spiral.xml")
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "dirStart=\"0\"", with: "")
            .replacingOccurrences(of: "<Start>0.00000000000000 0.00000000000000</Start>", with: "<Start>0 0</Start><PI>0 50</PI>")
        XCTAssertEqual(try parse(text).alignments[0].segments.count, 5)
    }
    func testStationInternalIsUnequatedStation() throws {
        let a = try TestSupport.alignment("station-equations.xml")
        XCTAssertEqual(a.stationEquations.map(\.geometricDistance), [100, 300])
        XCTAssertEqual(a.stationEquations[1].stationBack, 10400)
    }
    func testMissingStationBackDerived() throws {
        let text = String(decoding: try TestSupport.fixture("station-equations.xml"), as: UTF8.self)
            .replacingOccurrences(of: "staBack=\"10400\"", with: "")
        XCTAssertEqual(try parse(text).alignments[0].stationEquations[1].stationBack, 10400)
    }
    func testMultipleNamespacedAlignments() throws {
        let p = try LandXMLParser().parse(data: TestSupport.fixture("multiple-alignments.xml"))
        XCTAssertEqual(p.alignments.map(\.name), ["EAST", "NORTH"]); XCTAssertEqual(p.unit, .meter)
    }
    func testMalformedXML() throws { XCTAssertThrowsError(try LandXMLParser().parse(data: TestSupport.fixture("malformed.xml"))) }
    func testMissingAlignment() { XCTAssertThrowsError(try parse("<LandXML><Surfaces/></LandXML>")) }
    func testMissingCoordinates() { XCTAssertThrowsError(try parse("<LandXML><Alignments><Alignment><CoordGeom><Line><Start>0 0</Start></Line></CoordGeom></Alignment></Alignments></LandXML>")) }
    func testDisconnectedGeometryWarnsWithoutChangingCoordinates() throws {
        let text = String(decoding: try TestSupport.fixture("tangent-curve-tangent.xml"), as: UTF8.self)
            .replacingOccurrences(of: "<Start>100 200</Start>", with: "<Start>101 200</Start>")
        let a = try parse(text).alignments[0]
        XCTAssertTrue(a.warnings.contains { $0.contains("Disconnected") }); TestSupport.assertPoint(a.segments[2].start, 200, 101)
    }
    func testUnsupportedSpiralRejected() throws {
        let text = String(decoding: try TestSupport.fixture("spiral-curve-spiral.xml"), as: UTF8.self).replacingOccurrences(of: "clothoid", with: "bloss")
        XCTAssertThrowsError(try parse(text)) { error in
            guard case LandXMLParsingError.unsupportedGeometry = error else { return XCTFail("Expected unsupported geometry") }
        }
    }
    func testUnknownGeometryRejected() throws {
        let text = String(decoding: try TestSupport.fixture("tangent-only.xml"), as: UTF8.self).replacingOccurrences(of: "Line", with: "IrregularLine")
        XCTAssertThrowsError(try parse(text))
    }
    func testCurveOrientationMismatchRejected() throws {
        let text = String(decoding: try TestSupport.fixture("simple-curve.xml"), as: UTF8.self).replacingOccurrences(of: "ccw", with: "cw")
        XCTAssertThrowsError(try parse(text))
    }
    func testCenterDerivedFromRadiusAndLength() throws {
        let text = String(decoding: try TestSupport.fixture("simple-curve.xml"), as: UTF8.self).replacingOccurrences(of: "<Center>0 0</Center>", with: "")
        let a = try parse(text).alignments[0]; guard case .circularCurve(let c) = a.segments[0].geometry else { return XCTFail("Expected arc") }
        TestSupport.assertPoint(c.center, 0, 0)
    }
    func testCenterlessArcAmbiguityRejected() throws {
        let text = String(decoding: try TestSupport.fixture("simple-curve.xml"), as: UTF8.self)
            .replacingOccurrences(of: "<Center>0 0</Center>", with: "").replacingOccurrences(of: "length=\"157.07963267948966\"", with: "")
        XCTAssertThrowsError(try parse(text))
    }
    func testEntityDeclarationRejected() {
        XCTAssertThrowsError(try parse("<!DOCTYPE LandXML [<!ENTITY x 'expanded'>]><LandXML><Project name='&x;'/></LandXML>"))
    }
    func testInvalidStationEquationRejected() throws {
        let text = String(decoding: try TestSupport.fixture("station-equations.xml"), as: UTF8.self).replacingOccurrences(of: "staBack=\"10400\"", with: "staBack=\"10300\"")
        XCTAssertThrowsError(try parse(text))
    }
    func testDecreasingStationIncrementRejected() throws {
        let text = String(decoding: try TestSupport.fixture("station-equations.xml"), as: UTF8.self).replacingOccurrences(of: "<StaEquation", with: "<StaEquation staIncrement=\"decreasing\"")
        XCTAssertThrowsError(try parse(text))
    }
    func testDirectionConventionAndDegrees() throws {
        let text = String(decoding: try TestSupport.fixture("spiral-curve-spiral.xml"), as: UTF8.self)
            .replacingOccurrences(of: "directionUnit=\"radians\"", with: "directionUnit=\"decimal degrees\"")
            .replacingOccurrences(of: "dirStart=\"0\"", with: "dirStart=\"90\"")
            .replacingOccurrences(of: "dirEnd=\"0.25\"", with: "dirEnd=\"\(90 - 0.25 * 180 / Double.pi)\"")
            .replacingOccurrences(of: "dirStart=\"0.75\"", with: "dirStart=\"\(90 - 0.75 * 180 / Double.pi)\"")
            .replacingOccurrences(of: "dirEnd=\"1\"", with: "dirEnd=\"\(90 - 180 / Double.pi)\"")
        var options = LandXMLParserOptions(); options.directionConvention = .northClockwise
        XCTAssertEqual(try LandXMLParser(options: options).parse(data: Data(text.utf8)).alignments[0].segments.count, 5)
    }
    func testORDReverseCurveSample() throws {
        let a = try TestSupport.alignment("References/cw_reverse_curve.xml")
        XCTAssertEqual(a.segments.count, 5); XCTAssertTrue(a.warnings.isEmpty)
        XCTAssertEqual(a.totalGeometricLength, 3692.2578422137349, accuracy: 1e-6)
        guard case .circularCurve(let c) = a.segments[1].geometry else { return XCTFail("Expected curve") }
        XCTAssertEqual(c.rotation, .counterclockwise); XCTAssertEqual(c.length, 1198.652082090774, accuracy: 1e-6)
    }
    func testLargeProjectedSampleMetadata() throws {
        let p = try LandXMLParser().parse(data: TestSupport.fixture("References/sr82_synthetic.xml"))
        XCTAssertEqual(p.unit, .usSurveyFoot); XCTAssertEqual(p.coordinateSystemDescription, "NAD83(2011) / Mississippi East (ftUS)")
        XCTAssertEqual(p.alignments[0].totalGeometricLength, 17980.010636362913, accuracy: 1e-6)
    }
    func testSuppliedGISMultipleSample() throws {
        let p = try LandXMLParser().parse(data: TestSupport.fixture("References/gis-multiple.xml"))
        XCTAssertEqual(p.alignments.count, 2); XCTAssertEqual(p.unit, .internationalFoot)
        XCTAssertTrue(p.warnings.contains { $0.contains("Surfaces") })
    }
    func testSuppliedSyntheticCivil3DInconsistentSpiralRejected() throws {
        // The reference GIS implementation warps its approximate endpoint.
        // Exact clothoid geometry must reject this synthetic inconsistent End.
        XCTAssertThrowsError(try LandXMLParser().parse(data: TestSupport.fixture("References/civil3d-road-minimal.xml"))) { error in
            guard case LandXMLParsingError.malformedGeometry(let name, _) = error else { return XCTFail("Expected malformed spiral, got \(error)") }
            XCTAssertEqual(name, "Spiral")
        }
    }
}
