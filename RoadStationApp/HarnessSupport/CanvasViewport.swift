import Foundation
import RoadStationCore

public struct ScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A display-only, north-up planar transform. Large coordinate origins are
/// subtracted before scaling; the source engineering coordinates never change.
public struct CanvasViewport: Sendable {
    public let center: ProjectCoordinate
    public let scale: Double
    public let width: Double
    public let height: Double
    public let pan: ScreenPoint
    public init(bounds: SegmentBounds, width: Double, height: Double, zoom: Double = 1,
                pan: ScreenPoint = .init(x: 0, y: 0), padding: Double = 24) {
        self.width = max(1, width); self.height = max(1, height); self.pan = pan
        let spanX = max(0, bounds.maxX - bounds.minX)
        let spanY = max(0, bounds.maxY - bounds.minY)
        center = .init(x: bounds.minX + spanX / 2, y: bounds.minY + spanY / 2)
        let extent = max(spanX, spanY, 1e-9)
        let fitX = max(1, self.width - 2 * padding) / max(spanX, extent * 1e-6)
        let fitY = max(1, self.height - 2 * padding) / max(spanY, extent * 1e-6)
        scale = min(fitX, fitY) * Self.clampedZoom(zoom)
    }
    public static func clampedZoom(_ zoom: Double) -> Double {
        zoom.isFinite ? min(1000, max(0.1, zoom)) : 1
    }
    public func screen(_ point: ProjectCoordinate) -> ScreenPoint {
        .init(x: width / 2 + pan.x + (point.x - center.x) * scale,
              y: height / 2 + pan.y - (point.y - center.y) * scale)
    }
    public func coordinate(_ point: ScreenPoint) -> ProjectCoordinate {
        .init(x: center.x + (point.x - width / 2 - pan.x) / scale,
              y: center.y - (point.y - height / 2 - pan.y) / scale)
    }
}
