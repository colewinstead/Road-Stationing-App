import Foundation

public struct StationEquation: Codable, Equatable, Sendable {
    public let geometricDistance: Double
    public let stationBack: Double
    public let stationAhead: Double
    public init(geometricDistance: Double, stationBack: Double, stationAhead: Double) {
        self.geometricDistance = geometricDistance; self.stationBack = stationBack; self.stationAhead = stationAhead
    }
}

public enum EquationSide: String, Codable, Sendable { case back, ahead }
public struct StationLocation: Codable, Equatable, Sendable {
    public let geometricDistance: Double
    public let branchIndex: Int
    public let equationSide: EquationSide?
}
public enum StationResolution: Equatable, Sendable {
    case unique(StationLocation)
    case ambiguous([StationLocation])
    case outsideAlignment
}
