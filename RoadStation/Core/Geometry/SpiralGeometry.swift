import Foundation

/// Euler/clothoid: k(s)=k0+(k1-k0)s/L; theta(s)=theta0+k0*s+(k1-k0)s²/(2L).
/// Position integrates (cos(theta),sin(theta)) with phase-limited Gauss quadrature.
public struct SpiralSegment: Sendable {
    public let start: ProjectCoordinate
    public let end: ProjectCoordinate
    public let length: Double
    public let startHeading: Double // mathematical CCW angle from east, radians
    public let startCurvature: Double
    public let endCurvature: Double
    private let panelLength: Double
    private let checkpoints: [ProjectCoordinate]
    private let tolerances: GeometryTolerances
    public var bounds: SegmentBounds {
        // Every phase-panel chord is within K*h²/8 of the exact curve.
        let padding = max(abs(startCurvature), abs(endCurvature)) * panelLength * panelLength / 8 + tolerances.coordinate
        return SegmentBounds(points: checkpoints, padding: padding)
    }
    private static let maxPanelTurn = 0.2 // radians; prevents quadrature aliasing
    private static let maxPanels = 100_000
    private static let searchBudget = 100_000

    public init(start: ProjectCoordinate, length: Double, startHeading: Double,
                startCurvature: Double, endCurvature: Double, declaredEnd: ProjectCoordinate? = nil,
                tolerances: GeometryTolerances = .standard) throws {
        try tolerances.validate()
        guard start.isFinite, length.isFinite, length > tolerances.coordinate,
              startHeading.isFinite, startCurvature.isFinite, endCurvature.isFinite else {
            throw GeometryError.invalidGeometry("Clothoid parameters must be finite with positive length.")
        }
        let turnBound = length * max(abs(startCurvature), abs(endCurvature))
        guard turnBound.isFinite, turnBound <= Double(Self.maxPanels) * Self.maxPanelTurn else {
            throw GeometryError.invalidGeometry("Spiral exceeds supported numerical turn budget.")
        }
        let count = max(1, Int(ceil(turnBound / Self.maxPanelTurn)))
        let ds = length / Double(count)
        var cache = [start]
        for i in 0..<count {
            let v = try ClothoidQuadrature.integrate(from: Double(i) * ds, to: Double(i + 1) * ds,
                heading: startHeading, k0: startCurvature, rate: (endCurvature - startCurvature) / length,
                tolerance: tolerances.integration / Double(count))
            cache.append(ProjectCoordinate(x: cache.last!.x + v.x, y: cache.last!.y + v.y))
        }
        let computedEnd = cache.last!
        if let sourceEnd = declaredEnd {
            guard sourceEnd.isFinite, computedEnd.distance(to: sourceEnd) <= tolerances.importConsistency else {
                throw GeometryError.invalidGeometry("Clothoid parameters disagree with End; residual \(computedEnd.distance(to: sourceEnd)) project units.")
            }
        }
        self.start = start; self.length = length; self.startHeading = startHeading
        self.startCurvature = startCurvature; self.endCurvature = endCurvature
        self.panelLength = ds; self.checkpoints = cache; self.tolerances = tolerances
        self.end = ProjectCoordinate(x: computedEnd.x, y: computedEnd.y, z: declaredEnd?.z)
    }
    public func heading(at s: Double) -> Double {
        startHeading + startCurvature * s + (endCurvature - startCurvature) * s * s / (2 * length)
    }
    public func tangent(at s: Double) -> Vector2 { Vector2(x: cos(heading(at: s)), y: sin(heading(at: s))) }
    public func point(at distance: Double) throws -> ProjectCoordinate {
        let s = try GeometryUtilities.checkedDistance(distance, length: length, tolerance: tolerances.station)
        let index = min(checkpoints.count - 1, Int(s / panelLength))
        let a = Double(index) * panelLength
        let v = try ClothoidQuadrature.integrate(from: a, to: s, heading: startHeading,
            k0: startCurvature, rate: (endCurvature - startCurvature) / length, tolerance: tolerances.integration)
        return ProjectCoordinate(x: checkpoints[index].x + v.x, y: checkpoints[index].y + v.y,
                                 z: GeometryUtilities.elevation(start, end, fraction: s / length))
    }

    /// Global interval search. For a unit-speed curve with |k|<=K, the curve's
    /// deviation from a chord is <= K*h²/8. Chord-distance minus that bound is
    /// a lower bound on query distance. Subdivide all intervals that can beat
    /// the best candidate; stop only at the declared distance tolerance.
    public func closestPoint(to query: ProjectCoordinate) throws -> SegmentProjection {
        guard query.isFinite else { throw GeometryError.invalidGeometry("Query must be finite.") }
        var bestS = 0.0; var bestPoint = start; var bestDistance = start.distance(to: query)
        var nearCandidates: [(Double, Double)] = []
        func consider(_ s: Double) throws {
            let p = try point(at: s); let d = p.distance(to: query)
            if d < bestDistance { bestS = s; bestPoint = p; bestDistance = d }
        }
        try consider(length)
        struct Interval { let a: Double; let b: Double; let p: ProjectCoordinate; let q: ProjectCoordinate }
        var intervals: [Interval] = []
        // Initial phase bracketing; positions are exact integrals, not a polyline answer.
        let count = max(16, checkpoints.count - 1)
        for i in 0..<count {
            let a = length * Double(i) / Double(count); let b = length * Double(i + 1) / Double(count)
            intervals.append(Interval(a: a, b: b, p: try point(at: a), q: try point(at: b)))
            try consider((a + b) / 2)
        }
        let k = max(abs(startCurvature), abs(endCurvature))
        var visits = 0
        while let interval = intervals.popLast() {
            visits += 1
            guard visits < Self.searchBudget else { throw GeometryError.numericalFailure("Spiral closest-point search exceeded its convergence budget.") }
            let h = interval.b - interval.a
            let chord = GeometryUtilities.displacement(from: interval.p, to: interval.q)
            let norm2 = chord.dot(chord)
            let t = norm2 > 0 ? GeometryUtilities.clamp(GeometryUtilities.displacement(from: interval.p, to: query).dot(chord) / norm2, 0, 1) : 0
            let chordPoint = GeometryUtilities.translated(interval.p, by: chord, scale: t)
            let lower = max(0, chordPoint.distance(to: query) - k * h * h / 8 - tolerances.integration * 10)
            if lower > bestDistance + tolerances.tieDistance { continue }
            // Safeguarded minimization supplies a precise local candidate.
            if h <= length / Double(count) {
                let s = try minimize(query: query, a: interval.a, b: interval.b)
                try consider(s)
            }
            if bestDistance - lower <= tolerances.closestPoint || h <= tolerances.closestPoint {
                nearCandidates.append(((interval.a + interval.b) / 2, lower)); continue
            }
            let m = (interval.a + interval.b) / 2; let p = try point(at: m)
            try consider(m)
            intervals.append(Interval(a: interval.a, b: m, p: interval.p, q: p))
            intervals.append(Interval(a: m, b: interval.b, p: p, q: interval.q))
        }
        // Ambiguity is checked with actual refined positions, not lower bounds.
        var ambiguous = false
        for (s, lower) in nearCandidates where lower <= bestDistance + tolerances.tieDistance {
            if abs(s - bestS) > max(tolerances.closestPoint * 100, length / Double(count)) {
                let candidate = try minimize(query: query, a: max(0, s - length / Double(count)), b: min(length, s + length / Double(count)))
                if abs(candidate - bestS) > tolerances.station * 10,
                   abs(try point(at: candidate).distance(to: query) - bestDistance) <= tolerances.tieDistance { ambiguous = true }
            }
        }
        return SegmentProjection(distanceAlong: bestS, point: bestPoint, tangent: tangent(at: bestS),
                                 queryDistance: bestDistance, ambiguous: ambiguous)
    }
    private func minimize(query: ProjectCoordinate, a: Double, b: Double) throws -> Double {
        var low = a; var high = b
        // Solve stationary perpendicular condition in a bracket when possible.
        func gradient(_ s: Double) throws -> Double {
            GeometryUtilities.displacement(from: query, to: try point(at: s)).dot(tangent(at: s))
        }
        if try gradient(low) <= 0, try gradient(high) >= 0 {
            for _ in 0..<80 {
                let m = (low + high) / 2
                if try gradient(m) < 0 { low = m } else { high = m }
                if high - low <= tolerances.closestPoint { break }
            }
            return (low + high) / 2
        }
        return try point(at: low).distance(to: query) < point(at: high).distance(to: query) ? low : high
    }
}
