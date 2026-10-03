import Foundation

public enum ValidationRunner {
    public static func loadJSON(_ data: Data) throws -> [AlignmentValidationCase] {
        try JSONDecoder().decode([AlignmentValidationCase].self, from: data)
    }
    private static func signedOffset(_ value: Double, side: ValidationSide?) throws -> Double {
        guard value.isFinite else { throw GeometryError.invalidGeometry("Offset must be finite.") }
        guard let side else { return value }
        guard value >= 0, side != .ON || value == 0 else {
            throw GeometryError.invalidGeometry("LT/RT require a nonnegative offset magnitude; ON requires zero.")
        }
        return side == .RT ? -value : value
    }
    public static func run(cases: [AlignmentValidationCase], alignments: [Alignment]) -> [AlignmentValidationResult] {
        cases.map { c in
            do {
                guard [c.stationTolerance, c.offsetTolerance, c.coordinateTolerance].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                    throw GeometryError.invalidGeometry("Validation tolerances must be finite and nonnegative.")
                }
                let matches = alignments.filter { $0.name == c.alignmentName }
                guard matches.count == 1 else { throw GeometryError.invalidGeometry("Validation alignment name must match exactly one alignment: \(c.alignmentName).") }
                let engine = AlignmentEngine(alignment: matches[0])
                switch c.direction {
                case .forward:
                    guard let point = c.inputCoordinate, point.isFinite,
                          let station = c.expectedStation, station.isFinite,
                          let offsetMagnitude = c.expectedOffset, offsetMagnitude.isFinite else {
                        throw GeometryError.invalidGeometry("Forward validation requires coordinate and expected station/offset.")
                    }
                    let offset = try signedOffset(offsetMagnitude, side: c.expectedSide)
                    let value = try engine.stationOffset(point: point)
                    guard !value.nearestLocationIsAmbiguous else { throw GeometryError.invalidGeometry("Nearest alignment location is ambiguous.") }
                    var actualStation = value.displayedStation
                    if let side = c.equationSide {
                        // Independently recorded limit coordinates may be rounded. An
                        // explicit side selects its equation label while retaining the
                        // measured distance residual in the station comparison.
                        let equations = matches[0].stationEquations.filter {
                            abs($0.geometricDistance - value.geometricDistance) <= c.stationTolerance
                        }
                        guard equations.count == 1 else {
                            throw GeometryError.invalidGeometry("Explicit equationSide requires one equation within stationTolerance of the projected point.")
                        }
                        let equation = equations[0]
                        actualStation = (side == .back ? equation.stationBack : equation.stationAhead)
                            + value.geometricDistance - equation.geometricDistance
                    }
                    let actualSide: ValidationSide = abs(value.signedOffset) <= c.offsetTolerance ? .ON : (value.signedOffset > 0 ? .LT : .RT)
                    let ds = actualStation - station; let doffset = value.signedOffset - offset
                    return AlignmentValidationResult(validationCase: c,
                        passed: abs(ds) <= c.stationTolerance && abs(doffset) <= c.offsetTolerance && (c.expectedSide == nil || c.expectedSide == actualSide),
                        actualStation: actualStation, actualOffset: value.signedOffset, actualSide: actualSide, actualCoordinate: value.nearestPoint,
                        stationDifference: ds, offsetDifference: doffset, coordinateDifference: nil, error: nil)
                case .inverse:
                    guard let station = c.inputStation, station.isFinite, let offsetMagnitude = c.inputOffset,
                          let expected = c.expectedCoordinate, expected.isFinite else {
                        throw GeometryError.invalidGeometry("Inverse validation requires station/offset and expected coordinate.")
                    }
                    let offset = try signedOffset(offsetMagnitude, side: c.inputSide)
                    let value = try engine.coordinate(station: station, offset: offset, branchIndex: c.branchIndex)
                    let difference = value.coordinate.distance(to: expected)
                    return AlignmentValidationResult(validationCase: c, passed: difference <= c.coordinateTolerance,
                        actualStation: station, actualOffset: offset, actualSide: offset == 0 ? .ON : (offset > 0 ? .LT : .RT), actualCoordinate: value.coordinate,
                        stationDifference: nil, offsetDifference: nil, coordinateDifference: difference, error: nil)
                }
            } catch {
                return AlignmentValidationResult(validationCase: c, passed: false, actualStation: nil, actualOffset: nil, actualSide: nil,
                    actualCoordinate: nil, stationDifference: nil, offsetDifference: nil, coordinateDifference: nil,
                    error: error.localizedDescription)
            }
        }
    }
}
