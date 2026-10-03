import Foundation

public enum ValidationRunner {
    public static func loadJSON(_ data: Data) throws -> [AlignmentValidationCase] {
        try JSONDecoder().decode([AlignmentValidationCase].self, from: data)
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
                          let offset = c.expectedOffset, offset.isFinite else {
                        throw GeometryError.invalidGeometry("Forward validation requires coordinate and expected station/offset.")
                    }
                    let value = try engine.stationOffset(point: point)
                    guard !value.nearestLocationIsAmbiguous else { throw GeometryError.invalidGeometry("Nearest alignment location is ambiguous.") }
                    let ds = value.displayedStation - station; let doffset = value.signedOffset - offset
                    return AlignmentValidationResult(validationCase: c,
                        passed: abs(ds) <= c.stationTolerance && abs(doffset) <= c.offsetTolerance,
                        actualStation: value.displayedStation, actualOffset: value.signedOffset, actualCoordinate: value.nearestPoint,
                        stationDifference: ds, offsetDifference: doffset, coordinateDifference: nil, error: nil)
                case .inverse:
                    guard let station = c.inputStation, let offset = c.inputOffset,
                          let expected = c.expectedCoordinate, expected.isFinite else {
                        throw GeometryError.invalidGeometry("Inverse validation requires station/offset and expected coordinate.")
                    }
                    let value = try engine.coordinate(station: station, offset: offset, branchIndex: c.branchIndex)
                    let difference = value.coordinate.distance(to: expected)
                    return AlignmentValidationResult(validationCase: c, passed: difference <= c.coordinateTolerance,
                        actualStation: station, actualOffset: offset, actualCoordinate: value.coordinate,
                        stationDifference: nil, offsetDifference: nil, coordinateDifference: difference, error: nil)
                }
            } catch {
                return AlignmentValidationResult(validationCase: c, passed: false, actualStation: nil, actualOffset: nil,
                    actualCoordinate: nil, stationDifference: nil, offsetDifference: nil, coordinateDifference: nil,
                    error: error.localizedDescription)
            }
        }
    }
}
