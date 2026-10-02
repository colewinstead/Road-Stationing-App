import Foundation

public struct LineSegment: Sendable {
    public let start: ProjectCoordinate
    public let end: ProjectCoordinate
    public let length: Double
    public let tangent: Vector2
    public init(start: ProjectCoordinate, end: ProjectCoordinate) throws {
        let length = start.distance(to: end)
        guard start.isFinite, end.isFinite, length.isFinite, length > GeometryTolerances.standard.coordinate else {
            throw GeometryError.invalidGeometry("Line requires distinct finite endpoints.")
        }
        self.start = start; self.end = end; self.length = length
        tangent = Vector2(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
    }
    public func point(at distance: Double) throws -> ProjectCoordinate {
        let s = try GeometryUtilities.checkedDistance(distance, length: length)
        return ProjectCoordinate(x: start.x + tangent.x * s, y: start.y + tangent.y * s,
                                 z: GeometryUtilities.elevation(start, end, fraction: s / length))
    }
    public func closestPoint(to query: ProjectCoordinate) throws -> SegmentProjection {
        guard query.isFinite else { throw GeometryError.invalidGeometry("Query must be finite.") }
        let s = GeometryUtilities.clamp(GeometryUtilities.displacement(from: start, to: query).dot(tangent), 0, length)
        let p = try point(at: s)
        return SegmentProjection(distanceAlong: s, point: p, tangent: tangent,
                                 queryDistance: p.distance(to: query), ambiguous: false)
    }
}
