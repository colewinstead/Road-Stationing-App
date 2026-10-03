import Foundation

public struct StationingEngine: Sendable {
    public let alignment: Alignment
    public init(alignment: Alignment) { self.alignment = alignment }

    static func validate(equations: [StationEquation], startStation: Double, length: Double,
                         tolerances: GeometryTolerances) throws {
        var previousDistance = -Double.infinity; var shift = startStation
        for e in equations {
            guard e.geometricDistance.isFinite, e.stationBack.isFinite, e.stationAhead.isFinite,
                  e.geometricDistance >= 0, e.geometricDistance <= length,
                  e.geometricDistance - previousDistance > tolerances.station,
                  abs(e.stationBack - (e.geometricDistance + shift)) <= tolerances.importConsistency else {
                throw GeometryError.invalidStationEquation("Back station must match the preceding branch, with distinct equation locations within the alignment.")
            }
            previousDistance = e.geometricDistance; shift = e.stationAhead - e.geometricDistance
        }
    }
    /// Right-continuous stationing: at an equation return ahead unless back requested.
    public func station(at geometricDistance: Double, equationSide: EquationSide = .ahead) throws -> Double {
        let d = try GeometryUtilities.checkedDistance(geometricDistance, length: alignment.totalGeometricLength, tolerance: alignment.tolerances.station)
        var shift = alignment.startStation
        for e in alignment.stationEquations {
            if d == e.geometricDistance { return equationSide == .ahead ? e.stationAhead : e.stationBack }
            if d < e.geometricDistance { break }
            shift = e.stationAhead - e.geometricDistance
        }
        return d + shift
    }
    /// Both equation endpoint labels are recognized; no station ambiguity is hidden.
    public func resolve(station: Double) -> StationResolution {
        let candidates = locations(station: station)
        var locations: [StationLocation] = []
        for candidate in candidates {
            if !locations.contains(where: { abs($0.geometricDistance - candidate.geometricDistance) <= alignment.tolerances.station }) {
                locations.append(candidate)
            }
        }
        if locations.count == 1 { return .unique(locations[0]) }
        return locations.isEmpty ? .outsideAlignment : .ambiguous(locations)
    }
    private func locations(station: Double) -> [StationLocation] {
        guard station.isFinite else { return [] }
        var locations: [StationLocation] = []; var start = 0.0; var shift = alignment.startStation
        let equations = alignment.stationEquations
        for branch in 0...equations.count {
            let end = branch < equations.count ? equations[branch].geometricDistance : alignment.totalGeometricLength
            let rawDistance = station - shift
            // Floating-point cancellation at an endpoint is bounded in ULPs,
            // not by engineering station tolerance (which could swallow gaps).
            let rounding = 4 * max(station.ulp, shift.ulp, start.ulp, end.ulp)
            let d = GeometryUtilities.clamp(rawDistance, start, end)
            if rawDistance >= start - rounding, rawDistance <= end + rounding {
                let side: EquationSide? = branch > 0 && d == start ? .ahead : (branch < equations.count && d == end ? .back : nil)
                let location = StationLocation(geometricDistance: d, branchIndex: branch, equationSide: side)
                locations.append(location)
            }
            if branch < equations.count { start = end; shift = equations[branch].stationAhead - end }
        }
        return locations
    }
    public func location(station: Double, branchIndex: Int? = nil) throws -> StationLocation {
        // Branch selection must happen before distance deduplication: equivalent
        // positions can still belong to different equation branches.
        if let branchIndex {
            guard let location = locations(station: station).first(where: { $0.branchIndex == branchIndex }) else {
                throw GeometryError.stationOutsideAlignment(station)
            }
            return location
        }
        switch resolve(station: station) {
        case .outsideAlignment: throw GeometryError.stationOutsideAlignment(station)
        case .unique(let location):
            return location
        case .ambiguous(let locations):
            throw GeometryError.ambiguousStation(station, candidates: locations.map(\.geometricDistance))
        }
    }
}
