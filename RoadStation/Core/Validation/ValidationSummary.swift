import Foundation

/// Maxima include numeric comparisons from passing and failing cases. Errors
/// without numeric results are failures and do not masquerade as zero error.
public struct ValidationSummary: Sendable {
    public let cases: Int
    public let passed: Int
    public var failed: Int { cases - passed }
    public let maximumStationError: Double?
    public let maximumOffsetError: Double?
    public let maximumCoordinateError: Double?
    public init(results: [AlignmentValidationResult]) {
        cases = results.count; passed = results.filter(\.passed).count
        maximumStationError = results.compactMap(\.stationDifference).map { abs($0) }.max()
        maximumOffsetError = results.compactMap(\.offsetDifference).map { abs($0) }.max()
        maximumCoordinateError = results.compactMap(\.coordinateDifference).max()
    }
    public var text: String {
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "N/A (no numeric comparisons)" }
        return "Cases: \(cases)\nPassed: \(passed)\nFailed: \(failed)\nMaximum station error: \(number(maximumStationError))\nMaximum offset error: \(number(maximumOffsetError))\nMaximum coordinate error: \(number(maximumCoordinateError))"
    }
}
