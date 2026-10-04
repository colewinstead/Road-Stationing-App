import Foundation

/// WGS84 longitude/latitude in degrees. Height and epoch are outside Phase 2A.
public struct GeographicCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite else {
            throw CoordinateTransformationError.nonFiniteCoordinate
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw CoordinateTransformationError.invalidGeographicCoordinate
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}
