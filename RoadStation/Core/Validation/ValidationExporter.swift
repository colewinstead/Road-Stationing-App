import Foundation

public enum ValidationExporter {
    public static func json(_ results: [AlignmentValidationResult]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(results)
    }
    /// RFC 4180 CSV: all fields quoted, embedded quotes escaped, CRLF row endings.
    public static func csv(_ results: [AlignmentValidationResult]) -> String {
        let header = ["id", "alignment", "reference", "direction", "inputEasting", "inputNorthing", "inputStation", "inputOffset", "branchIndex",
                      "expectedStation", "expectedOffset", "expectedEasting", "expectedNorthing", "actualStation", "actualOffset", "actualEasting", "actualNorthing",
                      "stationDifference", "offsetDifference", "coordinateDifference", "stationTolerance", "offsetTolerance", "coordinateTolerance", "status", "error"]
        func n(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        func row(_ fields: [String]) -> String { fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
        var lines = [row(header)]
        for r in results {
            let c = r.validationCase
            lines.append(row([c.id, c.alignmentName, c.referenceSource, c.direction.rawValue,
                n(c.inputCoordinate?.x), n(c.inputCoordinate?.y), n(c.inputStation), n(c.inputOffset), c.branchIndex.map(String.init) ?? "",
                n(c.expectedStation), n(c.expectedOffset), n(c.expectedCoordinate?.x), n(c.expectedCoordinate?.y),
                n(r.actualStation), n(r.actualOffset), n(r.actualCoordinate?.x), n(r.actualCoordinate?.y),
                n(r.stationDifference), n(r.offsetDifference), n(r.coordinateDifference), n(c.stationTolerance), n(c.offsetTolerance), n(c.coordinateTolerance),
                r.passed ? "PASS" : "FAIL", r.error ?? ""]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
