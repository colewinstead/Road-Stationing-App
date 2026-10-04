import Foundation

public enum CoordinateTransformationError: Error, Equatable, Sendable {
    case invalidGeographicCoordinate
    case nonFiniteCoordinate
    case invalidEPSGCode(Int)
    case unresolvedCRS(CRSUnresolvedReason)
    case unsupportedCRS(String)
    case unsupportedAxes(String)
    case unsupportedUnits
    case incompatibleUnits
    case unexpectedHeight
    case backendUnavailable(String)
    case operationUnavailable(String)
    case transformationFailed(String)
}

extension CoordinateTransformationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidGeographicCoordinate: "Latitude must be within ±90° and longitude within ±180°."
        case .nonFiniteCoordinate: "Coordinates must be finite."
        case .invalidEPSGCode(let code): "Invalid EPSG code: \(code)."
        case .unresolvedCRS: "Project CRS is unresolved; select an explicit CRS before transforming."
        case .unsupportedCRS(let crs): "Unsupported horizontal CRS: \(crs)."
        case .unsupportedAxes(let crs): "CRS axes cannot be represented as Easting/Northing: \(crs)."
        case .unsupportedUnits: "Coordinate units are unknown or unsupported."
        case .incompatibleUnits: "Geographic degrees and project linear units cannot be interchanged."
        case .unexpectedHeight: "Phase 2A supports horizontal coordinates only; height cannot be transformed."
        case .backendUnavailable(let detail): "Projection backend unavailable: \(detail)"
        case .operationUnavailable(let detail): "Coordinate operation unavailable: \(detail)"
        case .transformationFailed(let detail): "Coordinate transformation failed: \(detail)"
        }
    }
}
