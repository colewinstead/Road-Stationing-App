import Foundation

public enum StationFormatter {
    public static func string(_ station: Double, precision: Int = 2) -> String {
        guard station.isFinite else { return "Invalid station" }
        let digits = min(6, max(0, precision)); let factor = pow(10.0, Double(digits))
        let rounded = (abs(station) * factor).rounded() / factor
        guard rounded.isFinite, rounded / 100 < Double(Int64.max) else { return "Invalid station" }
        let major = Int64(floor(rounded / 100)); let minor = rounded - Double(major) * 100
        let width = digits == 0 ? 2 : digits + 3
        let tail = String(format: "%0*.*f", locale: Locale(identifier: "en_US_POSIX"), width, digits, minor)
        return "\(station < 0 && rounded > 0 ? "-" : "")\(major)+\(tail)"
    }
    public static func parse(_ text: String) throws -> Double {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.split(separator: "+", omittingEmptySubsequences: false)
        if parts.count == 1, let value = Double(input), value.isFinite { return value }
        if parts.count == 2, let major = Double(parts[0]), let minor = Double(parts[1]),
           major.isFinite, minor.isFinite, major.rounded() == major, minor >= 0, minor < 100 {
            let value = (abs(major) * 100 + minor) * (input.hasPrefix("-") ? -1 : 1)
            if value.isFinite { return value }
        }
        throw GeometryError.invalidGeometry("Enter a numeric station or a value such as 427+38.42.")
    }
}
