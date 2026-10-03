import Foundation

public enum Rotation: String, Sendable {
    case clockwise, counterclockwise
    public var sign: Double { self == .clockwise ? -1 : 1 }
}

public struct CircularCurveSegment: Sendable {
    public let start: ProjectCoordinate
    public let end: ProjectCoordinate
    public let center: ProjectCoordinate
    public let radius: Double
    public let rotation: Rotation
    public let sweep: Double
    public let startAngle: Double
    public var length: Double { radius * sweep }
    public var bounds: SegmentBounds {
        let endAngle = startAngle + rotation.sign * sweep
        var points = [start, end,
            ProjectCoordinate(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle)),
            ProjectCoordinate(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle))]
        for angle in [0.0, Double.pi / 2, Double.pi, 3 * Double.pi / 2] {
            if GeometryUtilities.normalizedAngle(rotation.sign * (angle - startAngle)) <= sweep {
                points.append(ProjectCoordinate(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
            }
        }
        return SegmentBounds(points: points, padding: GeometryTolerances.standard.coordinate)
    }

    public init(start: ProjectCoordinate, end: ProjectCoordinate, center: ProjectCoordinate,
                rotation: Rotation, radius: Double? = nil, declaredLength: Double? = nil,
                tolerances: GeometryTolerances = .standard) throws {
        try tolerances.validate()
        let r = radius ?? start.distance(to: center)
        guard start.isFinite, end.isFinite, center.isFinite, r.isFinite, r > tolerances.coordinate,
              abs(start.distance(to: center) - r) <= tolerances.importConsistency,
              abs(end.distance(to: center) - r) <= tolerances.importConsistency else {
            throw GeometryError.invalidGeometry("Curve endpoints must lie on the declared radius.")
        }
        let a = atan2(start.y - center.y, start.x - center.x)
        let b = atan2(end.y - center.y, end.x - center.x)
        var sweep = GeometryUtilities.normalizedAngle(rotation.sign * (b - a))
        if sweep < tolerances.angle, let l = declaredLength,
           abs(l - GeometryUtilities.twoPi * r) <= tolerances.importConsistency { sweep = GeometryUtilities.twoPi }
        guard sweep > tolerances.angle else { throw GeometryError.invalidGeometry("Zero-length circular arc.") }
        if let l = declaredLength {
            guard l.isFinite, l > 0, abs(l - r * sweep) <= tolerances.importConsistency else {
                throw GeometryError.invalidGeometry("Curve rotation, endpoints, radius and declared length disagree.")
            }
        }
        self.start = start; self.end = end; self.center = center; self.radius = r
        self.rotation = rotation; self.sweep = sweep; self.startAngle = a
    }
    public func tangent(at distance: Double) -> Vector2 {
        let a = startAngle + rotation.sign * distance / radius
        return Vector2(x: -sin(a) * rotation.sign, y: cos(a) * rotation.sign)
    }
    public func point(at distance: Double) throws -> ProjectCoordinate {
        let s = try GeometryUtilities.checkedDistance(distance, length: length)
        let a = startAngle + rotation.sign * s / radius
        return ProjectCoordinate(x: center.x + radius * cos(a), y: center.y + radius * sin(a),
                                 z: GeometryUtilities.elevation(start, end, fraction: s / length))
    }
    public func closestPoint(to query: ProjectCoordinate) throws -> SegmentProjection {
        guard query.isFinite else { throw GeometryError.invalidGeometry("Query must be finite.") }
        let radialDistance = center.distance(to: query)
        let angle = atan2(query.y - center.y, query.x - center.x)
        let delta = GeometryUtilities.normalizedAngle(rotation.sign * (angle - startAngle))
        var candidates = [0.0, length]
        if radialDistance > GeometryTolerances.standard.coordinate, delta <= sweep { candidates.append(delta * radius) }
        let values = try candidates.map { s in (s, try point(at: s)) }
        let best = values.min { $0.1.distance(to: query) < $1.1.distance(to: query) }!
        let distance = best.1.distance(to: query)
        let tie = radialDistance <= GeometryTolerances.standard.coordinate || values.contains {
            abs($0.0 - best.0) > GeometryTolerances.standard.station &&
            abs($0.1.distance(to: query) - distance) <= GeometryTolerances.standard.tieDistance
        }
        return SegmentProjection(distanceAlong: best.0, point: best.1, tangent: tangent(at: best.0),
                                 queryDistance: distance, ambiguous: tie)
    }
}
