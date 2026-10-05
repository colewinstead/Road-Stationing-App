import Foundation
import RoadStationCore
import RoadStationAppleCRS

/// Geographic display data only. These samples never supply station/offset results.
public struct FieldMapDrawing: Sendable {
    public let polylines: [[GeographicCoordinate]]
    public let conversionMilliseconds: Double
    public var vertexCount: Int { polylines.reduce(0) { $0 + $1.count } }
}

public struct FieldMapMarkers: Sendable {
    public let snapshot: FieldPositionSnapshot
    public let phone: GeographicCoordinate
    public let nearest: GeographicCoordinate
    public let forward: GeographicCoordinate
    public func matches(_ current: FieldPositionSnapshot?) -> Bool { snapshot == current }
}

public enum FieldMapGeometry {
    public enum DisplayError: LocalizedError {
        case unsupportedExtent, drawingBudget
        public var errorDescription: String? {
            switch self {
            case .unsupportedExtent: "Map display cannot represent this extent. Use Engineering View."
            case .drawingBudget: "Map drawing exceeds the display subdivision limit. Use Engineering View."
            }
        }
    }

    /// Mercator meters for display error/direction, never engineering coordinates.
    public static func mapPoint(_ coordinate: GeographicCoordinate) throws -> ProjectCoordinate {
        guard abs(coordinate.latitude) <= 85.05112878 else { throw DisplayError.unsupportedExtent }
        return .init(x: 6_378_137 * coordinate.longitude * .pi / 180,
                     y: 6_378_137 * log(tan(.pi / 4 + coordinate.latitude * .pi / 360)))
    }

    public static func validateExtent(_ coordinates: [GeographicCoordinate]) throws {
        guard let first = coordinates.first else { throw DisplayError.unsupportedExtent }
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates {
            _ = try mapPoint(coordinate)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        // ponytail: longitude-wrap extents use the planar fallback; split wrapped overlays if needed later.
        guard maxLongitude - minLongitude < 180 else { throw DisplayError.unsupportedExtent }
    }

    public static func drawing(alignment: Alignment, transformer: any ProjectCoordinateTransformer,
                               maximumVertices: Int = 100_000) throws -> FieldMapDrawing {
        let started = Date()
        let samples = try AlignmentSampling.polylines(alignment: alignment)
        func geographic(_ points: [ProjectCoordinate]) throws -> [GeographicCoordinate] {
            try Task.checkCancellation()
            let xy = points.map { ProjectCoordinate(x: $0.x, y: $0.y) }
            if let proj = transformer as? PROJProjectCoordinateTransformer {
                return try proj.geographicCoordinates(from: xy)
            }
            return try xy.map { try transformer.geographicCoordinate(from: $0) }
        }
        guard samples.reduce(0, { $0 + $1.points.count }) <= maximumVertices else { throw DisplayError.drawingBudget }
        let converted = try geographic(samples.flatMap(\.points))
        var cursor = 0
        var lines = samples.map { polyline -> [(distance: Double, coordinate: GeographicCoordinate)] in
            let length = alignment.segments[polyline.segmentIndex].length
            return polyline.points.indices.map { index in
                defer { cursor += 1 }
                return (length * Double(index) / Double(polyline.points.count - 1), converted[cursor])
            }
        }
        for depth in 0...20 {
            let midpoints = try lines.enumerated().flatMap { segment, line in
                try line.indices.dropLast().map { index in
                    try alignment.segments[samples[segment].segmentIndex].geometry.point(at: (line[index].distance + line[index + 1].distance) / 2)
                }
            }
            let middleCoordinates = try geographic(midpoints)
            var middleIndex = 0, refined = false, count = 0
            var next: [[(distance: Double, coordinate: GeographicCoordinate)]] = []
            for line in lines {
                var points = [line[0]]
                count += 1
                for index in line.indices.dropLast() {
                    try Task.checkCancellation()
                    let a = line[index], b = line[index + 1], m = middleCoordinates[middleIndex]
                    middleIndex += 1
                    try validateExtent([a.coordinate, m, b.coordinate])
                    let pa = try mapPoint(a.coordinate), pb = try mapPoint(b.coordinate), pm = try mapPoint(m)
                    let chordMiddle = ProjectCoordinate(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
                    if pm.distance(to: chordMiddle) > 0.5 {
                        guard depth < 20 else { throw DisplayError.drawingBudget }
                        points.append(((a.distance + b.distance) / 2, m)); count += 1; refined = true
                    }
                    points.append(b); count += 1
                    guard count <= maximumVertices else { throw DisplayError.drawingBudget }
                }
                next.append(points)
            }
            lines = next
            if !refined { break }
        }
        let output = lines.map { $0.map(\.coordinate) }
        try validateExtent(output.flatMap { $0 })
        return FieldMapDrawing(polylines: output, conversionMilliseconds: Date().timeIntervalSince(started) * 1000)
    }

    public static func markers(snapshot: FieldPositionSnapshot,
                               transformer: any ProjectCoordinateTransformer) throws -> FieldMapMarkers {
        try Task.checkCancellation()
        guard transformer.definition == snapshot.crs.definition,
              transformer.definition.outputUnit == .linear(snapshot.unit) else {
            throw CoordinateTransformationError.operationUnavailable("Map transformer does not match the displayed CRS/units.")
        }
        let phone = try GeographicCoordinate(latitude: snapshot.sample.latitude, longitude: snapshot.sample.longitude)
        let point = snapshot.result.nearestPoint
        let nearest = try transformer.geographicCoordinate(from: .init(x: point.x, y: point.y))
        guard let metersPerUnit = snapshot.unit.metersPerUnit else {
            throw CoordinateTransformationError.unsupportedUnits
        }
        let span = 10 / metersPerUnit
        let forward = try transformer.geographicCoordinate(from: .init(
            x: point.x + snapshot.result.tangent.x * span,
            y: point.y + snapshot.result.tangent.y * span))
        try validateExtent([phone, nearest, forward])
        return FieldMapMarkers(snapshot: snapshot, phone: phone, nearest: nearest, forward: forward)
    }
}
