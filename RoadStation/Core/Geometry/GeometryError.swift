import Foundation

public enum GeometryError: Error, LocalizedError, Equatable {
    case invalidGeometry(String)
    case invalidStationEquation(String)
    case stationOutsideAlignment(Double)
    case ambiguousStation(Double, candidates: [Double])
    case numericalFailure(String)
    public var errorDescription: String? {
        switch self {
        case .invalidGeometry(let s): "Invalid geometry: \(s)"
        case .invalidStationEquation(let s): "Invalid station equation: \(s)"
        case .stationOutsideAlignment(let s): "Station or geometric distance \(s) is outside the alignment or in an equation gap."
        case .ambiguousStation(let s, let c): "Station \(s) is ambiguous; geometric distances: \(c). Select an equation branch."
        case .numericalFailure(let s): "Numerical calculation failed: \(s)"
        }
    }
}
