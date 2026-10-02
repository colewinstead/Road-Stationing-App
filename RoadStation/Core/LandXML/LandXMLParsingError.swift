import Foundation

public enum LandXMLParsingError: Error, LocalizedError, Equatable {
    case invalidXML(String)
    case missingAlignment
    case missingCoordinates(String)
    case malformedGeometry(String, String)
    case unsupportedGeometry(String)
    case invalidStationEquation(String)
    case invalidAttribute(String)
    public var errorDescription: String? {
        switch self {
        case .invalidXML(let s): "Invalid LandXML: \(s)"
        case .missingAlignment: "No horizontal alignment was found."
        case .missingCoordinates(let s): "Missing or invalid coordinates in \(s). Expected Northing Easting [Elevation]."
        case .malformedGeometry(let kind, let s): "Malformed \(kind): \(s)"
        case .unsupportedGeometry(let s): "Unsupported horizontal geometry: \(s). Import stopped to avoid incomplete stationing."
        case .invalidStationEquation(let s): "Invalid station equation: \(s)"
        case .invalidAttribute(let s): "Invalid LandXML attribute: \(s)"
        }
    }
}
