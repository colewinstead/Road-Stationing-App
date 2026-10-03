import Foundation

/// Absolute distances in project linear units; angles in radians.
public struct GeometryTolerances: Equatable, Sendable {
    public var coordinate: Double = 1e-7
    public var angle: Double = 1e-10
    public var station: Double = 1e-7
    public var closestPoint: Double = 1e-7
    public var integration: Double = 1e-10
    public var continuity: Double = 0.001
    public var importConsistency: Double = 0.001
    public var tieDistance: Double = 1e-7
    /// Resolvable tangent difference for approximate nearest-point solutions.
    public var tangentAmbiguity: Double = 1e-8
    public init() {}
    public static let standard = Self()
    func validate() throws {
        guard [coordinate, angle, station, closestPoint, integration, continuity, importConsistency, tieDistance, tangentAmbiguity]
            .allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw GeometryError.invalidGeometry("Numerical tolerances must be positive and finite.")
        }
    }
}

public enum GeometryUtilities {
    public static let twoPi = 2 * Double.pi
    public static func normalizedAngle(_ angle: Double) -> Double {
        let a = angle.truncatingRemainder(dividingBy: twoPi)
        return a < 0 ? a + twoPi : a
    }
    public static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
    public static func displacement(from a: ProjectCoordinate, to b: ProjectCoordinate) -> Vector2 {
        Vector2(x: b.x - a.x, y: b.y - a.y)
    }
    public static func translated(_ p: ProjectCoordinate, by v: Vector2, scale: Double) -> ProjectCoordinate {
        ProjectCoordinate(x: p.x + v.x * scale, y: p.y + v.y * scale)
    }
    static func elevation(_ start: ProjectCoordinate, _ end: ProjectCoordinate, fraction: Double) -> Double? {
        guard let a = start.z, let b = end.z else { return nil }
        return a + (b - a) * fraction
    }
    static func checkedDistance(_ s: Double, length: Double, tolerance: Double) throws -> Double {
        guard s.isFinite, s >= -tolerance, s <= length + tolerance else {
            throw GeometryError.stationOutsideAlignment(s)
        }
        return clamp(s, 0, length)
    }
}

public struct SegmentProjection: Sendable {
    public let distanceAlong: Double
    public let point: ProjectCoordinate
    public let tangent: Vector2
    public let queryDistance: Double
    public let ambiguous: Bool
}
