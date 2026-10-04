import Foundation
import XCTest
@testable import RoadStationCore

final class CRSModelTests: XCTestCase {
    func testValidGeographicCoordinatesIncludeBoundaries() throws {
        for (latitude, longitude) in [(0.0, 0.0), (-90, -180), (90, 180), (32.4, -89.2)] {
            let coordinate = try GeographicCoordinate(latitude: latitude, longitude: longitude)
            XCTAssertEqual(coordinate.latitude, latitude)
            XCTAssertEqual(coordinate.longitude, longitude)
        }
    }

    func testInvalidGeographicRangesAreRejectedWithoutWrapping() {
        for (latitude, longitude) in [(90.01, 0.0), (-90.01, 0), (0, 180.01), (0, -180.01)] {
            XCTAssertThrowsError(try GeographicCoordinate(latitude: latitude, longitude: longitude)) {
                XCTAssertEqual($0 as? CoordinateTransformationError, .invalidGeographicCoordinate)
            }
        }
    }

    func testNonFiniteGeographicCoordinates() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try GeographicCoordinate(latitude: value, longitude: 0)) {
                XCTAssertEqual($0 as? CoordinateTransformationError, .nonFiniteCoordinate)
            }
            XCTAssertThrowsError(try GeographicCoordinate(latitude: 0, longitude: value))
        }
    }

    func testEPSGIdentityAndSyntaxAreDistinctFromSupport() throws {
        XCTAssertEqual(try CoordinateReferenceSystem(epsgCode: 4326), .wgs84)
        XCTAssertEqual(CoordinateReferenceSystem.wgs84.identifier, "EPSG:4326")
        XCTAssertEqual(Set([try CoordinateReferenceSystem(epsgCode: 4326), .wgs84]).count, 1)
        // Positive syntax is accepted here; the external backend determines existence.
        XCTAssertNoThrow(try CoordinateReferenceSystem(epsgCode: 999999))
        for code in [0, -1, Int(Int32.max) + 1] {
            XCTAssertThrowsError(try CoordinateReferenceSystem(epsgCode: code))
        }
    }

    func testUnitsUseDistinctExactDefinitions() {
        XCTAssertEqual(ProjectUnit.meter.metersPerUnit, 1)
        XCTAssertEqual(ProjectUnit.internationalFoot.metersPerUnit, 0.3048)
        XCTAssertEqual(ProjectUnit.usSurveyFoot.metersPerUnit, 1200.0 / 3937.0)
        XCTAssertNotEqual(ProjectUnit.internationalFoot.metersPerUnit, ProjectUnit.usSurveyFoot.metersPerUnit)
        XCTAssertNil(ProjectUnit.unknown.metersPerUnit)
        XCTAssertNotEqual(CoordinateUnit.degree, .linear(.meter))
    }

    private func project(coordinateSystem: String, sourceName: String = "EPSG-6507") throws -> Project {
        let text = String(decoding: try TestSupport.fixture("tangent-only.xml"), as: UTF8.self)
            .replacingOccurrences(of: "<Alignments>", with: "\(coordinateSystem)<Alignments>")
        return try LandXMLParser().parse(data: Data(text.utf8), sourceName: sourceName)
    }

    func testUnresolvedCRSNeverGuessedFromNameDescriptionOrMagnitude() throws {
        for metadata in ["", "<CoordinateSystem name='EPSG:6507' desc='NAD83(2011) / Mississippi East (ftUS)'/>"] {
            let p = try project(coordinateSystem: metadata)
            XCTAssertEqual(p.crsResolution, .unresolved(.missingIdentification))
            XCTAssertEqual(p.alignments[0].segments[0].start, ProjectCoordinate(x: 1000, y: 2000, z: 10))
        }
        let plain = Project(name: "EPSG:4326", unit: .meter, alignments: [])
        XCTAssertEqual(plain.crsResolution, .unresolved(.missingIdentification))
    }

    func testLandXMLExplicitEPSGIdentifiesButDoesNotDeclareReadiness() throws {
        for code in ["6507", "EPSG:6507", " 6507 "] {
            let p = try project(coordinateSystem: "<CoordinateSystem epsgCode='\(code)'/>")
            XCTAssertEqual(p.crsResolution, .identified(try CoordinateReferenceSystem(epsgCode: 6507)))
            XCTAssertEqual(p.unit, .usSurveyFoot)
            XCTAssertEqual(p.alignments[0].segments[0].start, ProjectCoordinate(x: 1000, y: 2000, z: 10))
        }
    }

    func testInvalidExplicitIdentificationRemainsUnresolved() throws {
        for code in ["", "0", "-1", "6507junk", "ESRI:6507", "2147483648", "+6507"] {
            let p = try project(coordinateSystem: "<CoordinateSystem epsgCode='\(code)'/>")
            XCTAssertEqual(p.crsResolution, .unresolved(.invalidIdentification(code)))
        }
    }

    func testExplicitSyntheticFixtureIdentificationPreservesGeometry() throws {
        let p = try LandXMLParser().parse(data: TestSupport.fixture("References/sr82_synthetic.xml"))
        XCTAssertEqual(p.crsResolution, .identified(try CoordinateReferenceSystem(epsgCode: 6507)))
        XCTAssertEqual(p.alignments[0].totalGeometricLength, 17980.010636362913, accuracy: 1e-6)
    }
}
