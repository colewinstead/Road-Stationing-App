import Foundation
import XCTest
import RoadStationCore
import RoadStationAppleCRS
@testable import RoadStationFieldPosition

final class FieldMapGeometryTests: XCTestCase {
    private func transformer(_ code: Int = 3857, unit: ProjectUnit = .meter) throws -> PROJProjectCoordinateTransformer {
        try .init(resolution: .identified(.init(epsgCode: code)), outputUnit: .linear(unit))
    }
    private func alignment(_ start: ProjectCoordinate, _ end: ProjectCoordinate) throws -> Alignment {
        try .init(name: "Map test", geometries: [.line(.init(start: start, end: end))])
    }
    private func snapshot(_ alignment: Alignment, transformer: PROJProjectCoordinateTransformer,
                          point: ProjectCoordinate, unit: ProjectUnit = .meter, timestamp: Date = .init(timeIntervalSince1970: 2000)) throws -> FieldPositionSnapshot {
        let geographic = try transformer.geographicCoordinate(from: point)
        return .init(result: try AlignmentEngine(alignment: alignment).stationOffset(point: point), coordinate: point,
                     sample: .init(latitude: geographic.latitude, longitude: geographic.longitude,
                                   horizontalAccuracyMeters: 4, timestamp: timestamp, source: .developerInjection),
                     alignmentID: alignment.id, alignmentName: alignment.name,
                     crs: .init(definition: transformer.definition, provenance: .manual), unit: unit,
                     status: .locationReady, preciseAccuracy: true, projectionMilliseconds: 1)
    }

    func testIndependentReferenceUnitsAndDisplayOnlyHeight() throws {
        for unit in [ProjectUnit.meter, .internationalFoot, .usSurveyFoot] {
            let factor = try XCTUnwrap(unit.metersPerUnit)
            // Independently published spherical Mercator position at 1E,1N.
            let start = ProjectCoordinate(x: 111319.49079327357 / factor, y: 111325.1428663851 / factor, z: 50)
            let a = try alignment(start, .init(x: start.x + 100 / factor, y: start.y, z: 60))
            let drawing = try FieldMapGeometry.drawing(alignment: a, transformer: transformer(unit: unit))
            let first = try XCTUnwrap(drawing.polylines.first?.first)
            XCTAssertEqual(first.latitude, 1, accuracy: 1e-10)
            XCTAssertEqual(first.longitude, 1, accuracy: 1e-10)
            XCTAssertEqual(a.segments[0].start.z, 50)
            XCTAssertEqual(a.segments[0].end.z, 60)
        }
    }

    func testSubdivisionUsesProjectedSegmentAndKeepsGapsSeparate() throws {
        let t = try transformer(25832)
        let a = try Alignment(name: "Long UTM line and gap", geometries: [
            .line(.init(start: .init(x: 300000, y: 6000000), end: .init(x: 800000, y: 6500000))),
            .line(.init(start: .init(x: 801000, y: 6500000), end: .init(x: 802000, y: 6500000)))
        ])
        let drawing = try FieldMapGeometry.drawing(alignment: a, transformer: t)
        XCTAssertEqual(drawing.polylines.count, 2)
        XCTAssertGreaterThan(drawing.polylines[0].count, 2, "A projected straight line need not be straight on a geographic map")
        XCTAssertNotEqual(drawing.polylines[0].last, drawing.polylines[1].first)
        // Every generated vertex still belongs to the source projected line.
        for geographic in drawing.polylines[0] {
            let point = try t.projectCoordinate(from: geographic)
            XCTAssertEqual(point.y - point.x, 5700000, accuracy: 0.002)
        }
    }

    func testMarkerSnapshotIdentityAccuracyAndGridConvergence() throws {
        let t = try transformer(25832)
        let a = try alignment(.init(x: 691875.63214, y: 6098807.82501), .init(x: 691875.63214, y: 6099007.82501))
        let s = try snapshot(a, transformer: t, point: .init(x: 691880.63214, y: 6098907.82501))
        let markers = try FieldMapGeometry.markers(snapshot: s, transformer: t)
        XCTAssertEqual(markers.phone.latitude, s.sample.latitude)
        XCTAssertEqual(markers.phone.longitude, s.sample.longitude)
        XCTAssertEqual(markers.snapshot.sample.horizontalAccuracyMeters, 4)
        XCTAssertTrue(markers.matches(s))
        XCTAssertFalse(markers.matches(nil))
        let newer = try snapshot(a, transformer: t, point: s.coordinate, timestamp: s.sample.timestamp.addingTimeInterval(1))
        XCTAssertFalse(markers.matches(newer))
        XCTAssertThrowsError(try FieldMapGeometry.markers(snapshot: s, transformer: transformer()))
        XCTAssertEqual(markers.nearest.latitude, 55, accuracy: 1e-8)
        XCTAssertEqual(markers.nearest.longitude, 12, accuracy: 1e-8)
        let near = try FieldMapGeometry.mapPoint(markers.nearest), forward = try FieldMapGeometry.mapPoint(markers.forward)
        XCTAssertGreaterThan(forward.y, near.y)
        XCTAssertGreaterThan(abs(forward.x - near.x), 0.1, "Grid north must not be drawn as geographic north")
    }

    func testDrawingFailureBudgetAndUnsupportedExtentsAreExplicit() throws {
        let a = try alignment(.init(x: 0, y: 0), .init(x: 100, y: 100))
        XCTAssertThrowsError(try FieldMapGeometry.drawing(alignment: a, transformer: transformer(), maximumVertices: 1))
        XCTAssertThrowsError(try FieldMapGeometry.drawing(alignment: a, transformer: MapFailureTransformer(definition: transformer().definition)))
        XCTAssertThrowsError(try FieldMapGeometry.validateExtent([
            .init(latitude: 10, longitude: 179), .init(latitude: 10, longitude: -179)
        ]))
        XCTAssertThrowsError(try FieldMapGeometry.mapPoint(.init(latitude: 89, longitude: 0)))
    }

    func testCancelledDrawingDoesNotReturnPartialData() async throws {
        let a = try alignment(.init(x: 0, y: 0), .init(x: 100, y: 100))
        let t = try transformer()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FieldMapGeometry.drawing(alignment: a, transformer: t)
        }
        do { _ = try await task.value; XCTFail("Cancelled drawing published") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    #if os(macOS)
    func testProfileRealAndLargerAlignment() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..")
        let project = try LandXMLParser().parse(data: Data(contentsOf: root.appendingPathComponent("Validation/RealORD/CROSSGATES/CROSSGATES.xml")))
        // Explicit benchmark CRS only; CROSSGATES does not identify an EPSG and this does not validate its map placement.
        let real = try FieldMapGeometry.drawing(alignment: project.alignments[0], transformer: transformer(6507, unit: project.unit))
        print("MAP_PROFILE CROSSGATES vertices=\(real.vertexCount) ms=\(real.conversionMilliseconds)")
        let lines = try (0..<1000).map { index in
            SegmentGeometry.line(try LineSegment(start: .init(x: 500000 + Double(index) * 100, y: 6000000),
                                                end: .init(x: 500100 + Double(index) * 100, y: 6000000)))
        }
        let larger = try FieldMapGeometry.drawing(alignment: .init(name: "1000 segments", geometries: lines), transformer: transformer(25832))
        print("MAP_PROFILE generated vertices=\(larger.vertexCount) ms=\(larger.conversionMilliseconds)")
        XCTAssertEqual(larger.polylines.count, 1000)
    }
    #endif
}

private struct MapFailureTransformer: ProjectCoordinateTransformer {
    let definition: ResolvedCRS
    func projectCoordinate(from coordinate: GeographicCoordinate) throws -> ProjectCoordinate {
        throw CoordinateTransformationError.transformationFailed("Map test failure")
    }
    func geographicCoordinate(from coordinate: ProjectCoordinate) throws -> GeographicCoordinate {
        throw CoordinateTransformationError.transformationFailed("Map test failure")
    }
}
