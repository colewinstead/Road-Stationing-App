import Foundation
import RoadStationCore
import proj
import ProjectionResources

public enum CatalogUnit: String, Codable, Sendable {
    case meter, internationalFoot, usSurveyFoot, degree, unsupported
    public var label: String {
        switch self {
        case .meter: "Meters"
        case .internationalFoot: "International feet"
        case .usSurveyFoot: "US survey feet"
        case .degree: "Degrees"
        case .unsupported: "Other native units"
        }
    }
    public var projectUnit: ProjectUnit? {
        switch self {
        case .meter: .meter
        case .internationalFoot: .internationalFoot
        case .usSurveyFoot: .usSurveyFoot
        default: nil
        }
    }
}
public enum UnitCompatibility: Int, Sendable {
    case exact, convertible, incompatible
    public var label: String {
        switch self {
        case .exact: "Exact native-unit match"
        case .convertible: "Convertible — different native units"
        case .incompatible: "Incompatible with project units"
        }
    }
}
public struct CRSArea: Codable, Equatable, Sendable {
    public let name: String
    public let west, south, east, north: Double
    public init(name: String, west: Double, south: Double, east: Double, north: Double) {
        self.name = name; self.west = west; self.south = south; self.east = east; self.north = north
    }
    /// Closed official bounds. West > east denotes an antimeridian crossing.
    /// +/-180 represent the same meridian. Padding is ONLY a recommendation
    /// boundary buffer; it never changes official containment/warnings.
    public func contains(_ point: GeographicCoordinate, padding: Double = 0) -> Bool {
        guard point.latitude >= south-padding, point.latitude <= north+padding else { return false }
        let width = east >= west ? east-west : east+360-west
        if width+2*padding >= 360 { return true }
        let start = west-padding
        let distance = (point.longitude-start).truncatingRemainder(dividingBy: 360)
        let positive = distance < 0 ? distance+360 : distance
        return positive <= width+2*padding
    }
}
public struct StatePlaneMetadata: Codable, Equatable, Sendable {
    public let state, zone, conversion: String
}
public struct CRSCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public let code: Int
    public let name, datum: String
    public let nativeUnit: CatalogUnit
    public let nativeUnitName: String
    public let areas: [CRSArea]
    public let projected, deprecated: Bool
    public let statePlane: StatePlaneMetadata?
    public var id: Int { code }
    public var identifier: String { "EPSG:\(code)" }
    public func compatibility(with unit: ProjectUnit) -> UnitCompatibility {
        guard projected, let native = nativeUnit.projectUnit, unit.metersPerUnit != nil else { return .incompatible }
        return native == unit ? .exact : .convertible
    }
    public func contains(_ point: GeographicCoordinate, padding: Double = 0) -> Bool {
        areas.contains { $0.contains(point, padding: padding) }
    }
    var generationPreference: Int {
        if name.contains("NAD83(2011)") { return 0 }
        if name.contains("NSRS2007") { return 1 }
        if name.contains("HARN") { return 2 }
        if name.hasPrefix("NAD83 /") { return 3 }
        if name.hasPrefix("NAD27 /") { return 5 }
        return 4
    }
    var searchText: String {
        Self.normalized("\(identifier) \(name) \(datum) \(nativeUnit.label) \(nativeUnitName) \(statePlane?.state ?? "") \(statePlane?.zone ?? "")")
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
public struct CRSRecommendation: Identifiable, Sendable {
    public let entry: CRSCatalogEntry
    public let insideArea: Bool
    public let compatibility: UnitCompatibility
    public var id: Int { entry.id }
    public var reason: String {
        insideArea ? "Current location falls within the published area of use." : "Near a published area boundary. Confirm the alignment's actual CRS."
    }
}
public struct CRSCatalog: Decodable, Sendable {
    public let databaseSHA256, epsgVersion: String
    public let entries: [CRSCatalogEntry]
    private let searchIndex: [String]
    enum CodingKeys: String, CodingKey { case databaseSHA256, epsgVersion, entries }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        databaseSHA256 = try c.decode(String.self, forKey: .databaseSHA256)
        epsgVersion = try c.decode(String.self, forKey: .epsgVersion)
        entries = try c.decode([CRSCatalogEntry].self, forKey: .entries)
        searchIndex = entries.map(\.searchText)
    }
    public static func loadBundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.missingDatabase
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public var statePlaneEntries: [CRSCatalogEntry] { entries.filter { $0.projected && $0.statePlane != nil } }
    public func entry(code: Int) -> CRSCatalogEntry? { entries.first { $0.code == code } }
    public func search(_ query: String) -> [CRSCatalogEntry] {
        let words = CRSCatalogEntry.normalized(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let requestedCode = Int(query.replacingOccurrences(of: "EPSG:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines))
        return entries.indices.compactMap { i in words.allSatisfy { searchIndex[i].contains($0) } ? entries[i] : nil }
            .sorted { a, b in
                let aExact = a.code == requestedCode, bExact = b.code == requestedCode
                if aExact != bExact { return aExact }
                return a.code < b.code
            }
    }
    /// Ranking is qualitative; bounding boxes are not zone polygons. A 0.05°
    /// buffer exposes adjacent candidates near boundaries, never chooses one.
    public func recommendations(at point: GeographicCoordinate?, projectUnit: ProjectUnit) -> [CRSRecommendation] {
        guard let point else { return [] }
        return statePlaneEntries.filter { $0.contains(point, padding: 0.05) }.map {
            CRSRecommendation(entry: $0, insideArea: $0.contains(point), compatibility: $0.compatibility(with: projectUnit))
        }.sorted { a, b in
            if a.insideArea != b.insideArea { return a.insideArea }
            if a.compatibility != b.compatibility { return a.compatibility.rawValue < b.compatibility.rawValue }
            if a.entry.deprecated != b.entry.deprecated { return !a.entry.deprecated }
            if a.entry.generationPreference != b.entry.generationPreference { return a.entry.generationPreference < b.entry.generationPreference }
            return a.entry.code < b.entry.code
        }
    }
}
public enum CatalogError: Error { case missingDatabase, unknownCRS, unsupportedAxes }
/// One immutable session cache, built off MainActor. No C handles are cached.
public actor CRSCatalogStore {
    public static let shared = CRSCatalogStore()
    private var task: Task<CRSCatalog, Error>?
    public func catalog() async throws -> CRSCatalog {
        if let task { return try await task.value }
        let build = Task.detached(priority: .userInitiated) { try CRSCatalog.loadBundled() }
        task = build
        do { return try await build.value }
        catch { task = nil; throw error }
    }
}

/// Runtime inspection verifies the generated metadata against the installed C
/// API. Each inspection owns and destroys its context and objects on one thread.
public enum PROJCatalogInspection {
    public struct Metadata: Sendable {
        public let name: String
        public let projected: Bool
        public let unitCode: String
        public let area: CRSArea?
    }
    public static func inspect(code: Int) throws -> Metadata {
        guard let path = RSProjectionDatabasePath(), let context = proj_context_create() else { throw CatalogError.missingDatabase }
        defer { proj_context_destroy(context) }
        proj_log_level(context, PJ_LOG_NONE)
        proj_context_set_enable_network(context, 0)
        guard proj_context_set_database_path(context, path, nil, nil) != 0 else { throw CatalogError.missingDatabase }
        guard let crs = proj_create(context, "EPSG:\(code)") else { throw CatalogError.unknownCRS }
        defer { proj_destroy(crs) }
        guard let cs = proj_crs_get_coordinate_system(context, crs) else { throw CatalogError.unsupportedAxes }
        defer { proj_destroy(cs) }
        guard proj_cs_get_axis_count(context, cs) == 2 else { throw CatalogError.unsupportedAxes }
        var unitCode: UnsafePointer<CChar>?
        guard proj_cs_get_axis_info(context, cs, 0, nil, nil, nil, nil, nil, nil, &unitCode) != 0 else { throw CatalogError.unsupportedAxes }
        var west = 0.0, south = 0.0, east = 0.0, north = 0.0
        var areaName: UnsafePointer<CChar>?
        let validArea = proj_get_area_of_use(context, crs, &west, &south, &east, &north, &areaName) != 0
        guard let name = proj_get_name(crs) else { throw CatalogError.unknownCRS }
        return Metadata(name: String(cString: name), projected: proj_get_type(crs) == PJ_TYPE_PROJECTED_CRS,
            unitCode: unitCode.map { String(cString: $0) } ?? "",
            area: validArea ? CRSArea(name: areaName.map { String(cString: $0) } ?? "", west: west, south: south, east: east, north: north) : nil)
    }
}
