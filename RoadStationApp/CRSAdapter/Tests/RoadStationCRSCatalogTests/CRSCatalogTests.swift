import XCTest
import RoadStationCore
@testable import RoadStationCRSCatalog

final class CRSCatalogTests: XCTestCase {
    func testNationwideStatePlaneMembershipAndExclusions() throws {
        let catalog = try CRSCatalog.loadBundled()
        XCTAssertEqual(catalog.epsgVersion, "v11.004")
        XCTAssertEqual(catalog.entries.count, 6280)
        XCTAssertEqual(catalog.statePlaneEntries.count, 1081)
        XCTAssertEqual(Set(catalog.statePlaneEntries.map { $0.statePlane!.state }).count, 53)
        for state in ["Alaska", "Hawaii", "California", "Tennessee", "Wyoming", "Puerto Rico", "St. Croix"] {
            XCTAssertTrue(catalog.statePlaneEntries.contains { $0.statePlane?.state == state })
        }
        for code in [26748, 26749, 26750, 5623, 5624, 5625] { XCTAssertNotNil(catalog.entry(code: code)?.statePlane) }
        for code in [4326, 3857, 32616] { XCTAssertNil(try XCTUnwrap(catalog.entry(code: code)).statePlane) }
        XCTAssertFalse(try XCTUnwrap(catalog.entry(code: 4326)).projected)
        XCTAssertNil(catalog.entry(code: 4979)) // 3D excluded
        XCTAssertNil(catalog.entry(code: 5703)) // vertical excluded
        XCTAssertNil(catalog.entry(code: 7407)) // compound excluded
    }
    func testMississippiMetadataMatchesCompiledInstalledPROJAPI() throws {
        let catalog = try CRSCatalog.loadBundled()
        for (code, zone) in [(6507, "East"), (6510, "West")] {
            let entry = try XCTUnwrap(catalog.entry(code: code))
            let live = try PROJCatalogInspection.inspect(code: code)
            XCTAssertEqual(entry.name, "NAD83(2011) / Mississippi \(zone) (ftUS)")
            XCTAssertEqual(live.name, entry.name)
            XCTAssertEqual(live.unitCode, "9003")
            XCTAssertEqual(entry.nativeUnit, .usSurveyFoot)
            XCTAssertTrue(entry.projected && live.projected)
            XCTAssertEqual(entry.statePlane?.state, "Mississippi")
            let area = try XCTUnwrap(live.area)
            XCTAssertTrue(entry.areas.contains(area))
            XCTAssertGreaterThan(area.north, 34)
            XCTAssertEqual(area.west, code == 6507 ? -89.97 : -91.65)
            XCTAssertEqual(area.east, code == 6507 ? -88.09 : -89.37)
            XCTAssertEqual(area.south, code == 6507 ? 30.01 : 31.0)
            XCTAssertEqual(area.north, 35.01)
            XCTAssertTrue(entry.datum.contains("2011"))
        }
        XCTAssertEqual(try XCTUnwrap(catalog.entry(code: 26994)).nativeUnit, .meter)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(code: 2222)).nativeUnit, .internationalFoot)
    }
    func testAxisAndTypeInspectionWithCompiledPinnedAPI() throws {
        let geographic = try PROJCatalogInspection.inspect(code: 4326)
        XCTAssertFalse(geographic.projected)
        XCTAssertEqual(geographic.unitCode, "9122")
        XCTAssertThrowsError(try PROJCatalogInspection.inspect(code: 999999))
        XCTAssertThrowsError(try PROJCatalogInspection.inspect(code: 4979))
    }
    func testUnitsDoNotConflateFeetOrRejectConvertibleMeters() throws {
        let catalog = try CRSCatalog.loadBundled()
        let us = try XCTUnwrap(catalog.entry(code: 6510))
        XCTAssertEqual(us.compatibility(with: .usSurveyFoot), .exact)
        XCTAssertEqual(us.compatibility(with: .internationalFoot), .convertible)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(code: 26994)).compatibility(with: .usSurveyFoot), .convertible)
        XCTAssertEqual(try XCTUnwrap(catalog.entry(code: 4326)).compatibility(with: .meter), .incompatible)
        XCTAssertEqual(us.compatibility(with: .unknown), .incompatible)
    }
    func testSearchCodeNameStateDatumUnitAndEmpty() throws {
        let catalog = try CRSCatalog.loadBundled()
        for (query, code) in [("Mississippi West",6510),("Mississippi East",6507),("6510",6510),("EPSG:6507",6507),
            ("NAD83 2011",6510),("survey foot",6510),("Tennessee",6576)] {
            XCTAssertTrue(catalog.search(query).contains { $0.code == code }, query)
        }
        XCTAssertTrue(catalog.search("nothing-matches-XYZ").isEmpty)
        XCTAssertTrue(catalog.search("").isEmpty)
        XCTAssertTrue(catalog.search("international feet").allSatisfy { $0.nativeUnit == .internationalFoot })
        XCTAssertEqual(catalog.search("6510").first?.code, 6510)
    }
    func testRecommendationContainmentUnitModernDatumAndBoundaryCandidates() throws {
        let catalog = try CRSCatalog.loadBundled()
        let point = try GeographicCoordinate(latitude: 32.3, longitude: -90.2)
        let recommendations = catalog.recommendations(at: point, projectUnit: .usSurveyFoot)
        XCTAssertEqual(recommendations.first?.entry.code, 6510)
        XCTAssertTrue(recommendations.first!.insideArea)
        XCTAssertEqual(recommendations.first?.compatibility, .exact)
        XCTAssertTrue(recommendations.contains { $0.entry.name.hasPrefix("NAD27") })
        XCTAssertTrue(recommendations.contains { $0.entry.name.hasPrefix("NAD83 /") })
        XCTAssertEqual(catalog.recommendations(at: point, projectUnit: .meter).first?.compatibility, .exact)
        let west = try XCTUnwrap(catalog.entry(code: 6510)).areas[0]
        let boundary = try GeographicCoordinate(latitude: 32.3, longitude: west.east)
        let choices = catalog.recommendations(at: boundary, projectUnit: .usSurveyFoot)
        XCTAssertTrue(choices.contains { $0.entry.code == 6510 })
        XCTAssertTrue(choices.contains { $0.entry.code == 6507 })
        XCTAssertTrue(catalog.recommendations(at: nil, projectUnit: .usSurveyFoot).isEmpty)
    }
    func testClosedBoundsAntimeridianAndRecommendationBuffer() throws {
        let crossing = CRSArea(name: "crossing", west: 170, south: -10, east: -170, north: 10)
        for longitude in [170.0, -170, 180, -180, 179, -179] {
            XCTAssertTrue(crossing.contains(try GeographicCoordinate(latitude: 10, longitude: longitude)))
        }
        XCTAssertFalse(crossing.contains(try GeographicCoordinate(latitude: 0, longitude: 0)))
        let near = try GeographicCoordinate(latitude: 0, longitude: 169.98)
        XCTAssertFalse(crossing.contains(near))
        XCTAssertTrue(crossing.contains(near, padding: 0.05))
        let global = CRSArea(name: "World", west: -180, south: -90, east: 180, north: 90)
        XCTAssertTrue(global.contains(try GeographicCoordinate(latitude: -90, longitude: 180)))
        let edge = CRSArea(name: "edge", west: -180, south: 0, east: -170, north: 10)
        XCTAssertTrue(edge.contains(try GeographicCoordinate(latitude: 5, longitude: 180)))
    }
    func testCatalogBuildAndSearchPerformance() throws {
        let start = Date()
        let catalog = try CRSCatalog.loadBundled()
        let loaded = Date().timeIntervalSince(start)*1000
        let queries = ["Mississippi West", "NAD83 2011", "survey foot", "6510", "Tennessee"]
        let searchStart = Date()
        for _ in 0..<20 { for query in queries { _ = catalog.search(query) } }
        print("CRS catalog: \(catalog.entries.count) entries; decode+index \(loaded) ms; search mean \(Date().timeIntervalSince(searchStart)*10) ms (100 queries)")
    }
}
