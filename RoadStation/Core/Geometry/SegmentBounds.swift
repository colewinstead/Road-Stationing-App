import Foundation

public struct SegmentBounds: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double
    public init(points: [ProjectCoordinate], padding: Double = 0) {
        minX = (points.map(\.x).min() ?? 0) - padding
        minY = (points.map(\.y).min() ?? 0) - padding
        maxX = (points.map(\.x).max() ?? 0) + padding
        maxY = (points.map(\.y).max() ?? 0) + padding
    }
    /// A lower bound on distance to all geometry within this box.
    public func distance(to point: ProjectCoordinate) -> Double {
        hypot(max(0, minX - point.x, point.x - maxX), max(0, minY - point.y, point.y - maxY))
    }
    public func contains(_ point: ProjectCoordinate) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
