import Foundation
import RoadStationCore

public enum EntrySide: String, CaseIterable, Sendable { case LT, RT, ON }
public enum ManualQuery {
    public static func finiteNumber(_ text: String, name: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            throw GeometryError.invalidGeometry("\(name) requires a finite decimal number (use a decimal point, without thousands separators).")
        }
        return value
    }
    public static func coordinate(easting: String, northing: String) throws -> ProjectCoordinate {
        try .init(x: finiteNumber(easting, name: "Easting"), y: finiteNumber(northing, name: "Northing"))
    }
    public static func station(_ text: String) throws -> Double {
        try StationFormatter.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public static func signedOffset(magnitude: String, side: EntrySide) throws -> Double {
        let value = try finiteNumber(magnitude, name: "Offset magnitude")
        guard value >= 0, side != .ON || value == 0 else {
            throw GeometryError.invalidGeometry("Use a nonnegative offset magnitude. ON requires zero offset.")
        }
        return side == .RT ? -value : value
    }
}
