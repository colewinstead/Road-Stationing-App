import Foundation

public enum OffsetSide: String, Codable, Sendable { case left, right, onAlignment }
public struct StationOffsetResult: Sendable {
    public let geometricDistance: Double
    public let displayedStation: Double
    public let signedOffset: Double
    public let side: OffsetSide
    public let nearestPoint: ProjectCoordinate
    public let nearestSegmentIndex: Int
    public let distanceFromQueryPointToAlignment: Double
    public let tangent: Vector2
    public var bearing: Double { tangent.bearing }
    public let longitudinalResidual: Double
    public let nearestLocationIsAmbiguous: Bool
    public let segmentType: String
    public var formattedStation: String { StationFormatter.string(displayedStation) }
}
public struct CoordinateResult: Sendable {
    public let coordinate: ProjectCoordinate
    public let geometricDistance: Double
    public let nearestSegmentIndex: Int
    public let stationLocation: StationLocation
}
