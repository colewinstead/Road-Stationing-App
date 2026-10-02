import Foundation

public enum SegmentGeometry: Sendable {
    case line(LineSegment)
    case circularCurve(CircularCurveSegment)
    case spiral(SpiralSegment)
    public var start: ProjectCoordinate {
        switch self { case .line(let g): g.start; case .circularCurve(let g): g.start; case .spiral(let g): g.start }
    }
    public var end: ProjectCoordinate {
        switch self { case .line(let g): g.end; case .circularCurve(let g): g.end; case .spiral(let g): g.end }
    }
    public var length: Double {
        switch self { case .line(let g): g.length; case .circularCurve(let g): g.length; case .spiral(let g): g.length }
    }
    public var typeName: String {
        switch self { case .line: "Line"; case .circularCurve: "Circular curve"; case .spiral: "Clothoid" }
    }
    public func point(at distance: Double) throws -> ProjectCoordinate {
        switch self { case .line(let g): try g.point(at: distance); case .circularCurve(let g): try g.point(at: distance); case .spiral(let g): try g.point(at: distance) }
    }
    public func tangent(at distance: Double) -> Vector2 {
        switch self { case .line(let g): g.tangent; case .circularCurve(let g): g.tangent(at: distance); case .spiral(let g): g.tangent(at: distance) }
    }
    public func closestPoint(to point: ProjectCoordinate) throws -> SegmentProjection {
        switch self { case .line(let g): try g.closestPoint(to: point); case .circularCurve(let g): try g.closestPoint(to: point); case .spiral(let g): try g.closestPoint(to: point) }
    }
}

public struct AlignmentSegment: Sendable {
    public let geometry: SegmentGeometry
    public let geometricStartDistance: Double
    public var geometricEndDistance: Double { geometricStartDistance + length }
    public var start: ProjectCoordinate { geometry.start }
    public var end: ProjectCoordinate { geometry.end }
    public var length: Double { geometry.length }
}
