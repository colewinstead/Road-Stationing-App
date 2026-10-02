import Foundation

/// Generic planar coordinates, in the project's unconverted linear units.
/// Z is source metadata only: all Phase 1 calculations are horizontal (2D).
public struct ProjectCoordinate: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double?
    public init(x: Double, y: Double, z: Double? = nil) { self.x = x; self.y = y; self.z = z }
    public var isFinite: Bool { x.isFinite && y.isFinite && (z?.isFinite ?? true) }
    public func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

public struct Vector2: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var leftNormal: Self { Self(x: -y, y: x) }
    public func dot(_ v: Self) -> Double { x * v.x + y * v.y }
    public func cross(_ v: Self) -> Double { x * v.y - y * v.x }
    /// Survey bearing: clockwise from north, radians in [0, 2π).
    public var bearing: Double { GeometryUtilities.normalizedAngle(atan2(x, y)) }
}

/// Future projection adapters implement this outside the geometry engine.
public protocol ProjectCoordinateTransformer: Sendable {
    func projectCoordinate(latitude: Double, longitude: Double) throws -> ProjectCoordinate
}
