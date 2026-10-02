import Foundation

public enum OffsetEngine {
    /// Positive left: cross(unit tangent, query - centerline); negative right.
    public static func signedOffset(tangent: Vector2, from centerline: ProjectCoordinate, to query: ProjectCoordinate) -> Double {
        tangent.cross(GeometryUtilities.displacement(from: centerline, to: query))
    }
    public static func coordinate(centerline: ProjectCoordinate, tangent: Vector2, offset: Double) -> ProjectCoordinate {
        GeometryUtilities.translated(centerline, by: tangent.leftNormal, scale: offset)
    }
}
