/// Implemented outside RoadStationCore. Geographic inputs/outputs are WGS84 degrees.
/// Projected output is always X=Easting, Y=Northing in `definition.outputUnit`.
/// Geographic destination output (including EPSG:4326 identity) is X=longitude,
/// Y=latitude in degrees, and must never be fed to the planar geometry engine.
public protocol ProjectCoordinateTransformer: Sendable {
    var definition: ResolvedCRS { get }
    func projectCoordinate(from coordinate: GeographicCoordinate) throws -> ProjectCoordinate
    func geographicCoordinate(from coordinate: ProjectCoordinate) throws -> GeographicCoordinate
}

public extension ProjectCoordinateTransformer {
    func projectCoordinate(latitude: Double, longitude: Double) throws -> ProjectCoordinate {
        try projectCoordinate(from: GeographicCoordinate(latitude: latitude, longitude: longitude))
    }
}

public extension ProjectUnit {
    /// Exact definitions: international foot = 0.3048 m; US survey foot = 1200/3937 m.
    /// These factors apply only at a transformation boundary, never to imported geometry.
    var metersPerUnit: Double? {
        switch self {
        case .meter: 1
        case .internationalFoot: 0.3048
        case .usSurveyFoot: 1200.0 / 3937.0
        case .unknown: nil
        }
    }
}
