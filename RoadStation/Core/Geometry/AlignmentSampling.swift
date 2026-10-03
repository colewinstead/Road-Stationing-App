import Foundation

public struct AlignmentPolyline: Sendable {
    public let segmentIndex: Int
    public let points: [ProjectCoordinate]
}

/// Display-only samples for a future native engineering canvas. Geometry queries
/// never use these polylines. Each source segment remains separate (no gap joins).
public enum AlignmentSampling {
    public static func polylines(alignment: Alignment, maximumChordError: Double = 0.05) throws -> [AlignmentPolyline] {
        guard maximumChordError.isFinite, maximumChordError > 0 else {
            throw GeometryError.invalidGeometry("Display chord error must be positive and finite.")
        }
        return try alignment.segments.enumerated().map { index, segment in
            let curvature: Double
            switch segment.geometry {
            case .line: curvature = 0
            case .circularCurve(let curve): curvature = 1 / curve.radius
            case .spiral(let spiral): curvature = max(abs(spiral.startCurvature), abs(spiral.endCurvature))
            }
            let interval = curvature == 0 ? segment.length : sqrt(8 * maximumChordError / curvature)
            let requested = ceil(segment.length / interval)
            guard requested.isFinite, requested <= 100_000 else {
                throw GeometryError.invalidGeometry("Display sampling exceeds 100,000 intervals per segment.")
            }
            let count = max(1, Int(requested))
            let points = try (0...count).map { i in try segment.geometry.point(at: segment.length * Double(i) / Double(count)) }
            return AlignmentPolyline(segmentIndex: index, points: points)
        }
    }
}
