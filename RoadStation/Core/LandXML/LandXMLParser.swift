import Foundation

public enum LandXMLDirectionConvention: Sendable {
    /// Matches the supplied ORD fixtures (dir=0 for an eastbound line).
    case eastCounterclockwise
    case northCounterclockwise
    case northClockwise
    func heading(_ value: Double) -> Double {
        switch self { case .eastCounterclockwise: value; case .northCounterclockwise: .pi / 2 + value; case .northClockwise: .pi / 2 - value }
    }
}
public struct LandXMLParserOptions: Sendable {
    public var tolerances: GeometryTolerances = .standard
    public var directionConvention: LandXMLDirectionConvention = .eastCounterclockwise
    public init() {}
}

public struct LandXMLParser: Sendable {
    public let options: LandXMLParserOptions
    public init(options: LandXMLParserOptions = LandXMLParserOptions()) { self.options = options }
    /// LandXML coordinate text is N E [Z], always converted to internal E N [Z].
    public static func coordinate(from text: String) throws -> ProjectCoordinate {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 2 || tokens.count == 3 else { throw LandXMLParsingError.missingCoordinates(text) }
        let numbers = tokens.compactMap { Double($0) }
        guard numbers.count == tokens.count, numbers.allSatisfy(\.isFinite) else {
            throw LandXMLParsingError.missingCoordinates(text)
        }
        return ProjectCoordinate(x: numbers[1], y: numbers[0], z: numbers.count == 3 ? numbers[2] : nil)
    }
    public func parse(url: URL) throws -> Project { try parse(data: Data(contentsOf: url), sourceName: url.deletingPathExtension().lastPathComponent) }
    public func parse(data: Data, sourceName: String = "Imported project") throws -> Project {
        let root = try XMLDocument.parse(data)
        guard root.name == "LandXML" else { throw LandXMLParsingError.invalidXML("Root must be LandXML.") }
        let version = root.attributes["version"]
        if let version, !["1.0", "1.1", "1.2"].contains(version) { throw LandXMLParsingError.invalidXML("Unsupported LandXML version \(version).") }
        let unitsNode = root.child("Units")?.children.first
        let unitText = unitsNode?.attributes["linearUnit"]?.lowercased()
        let unit: ProjectUnit = switch unitText {
        case "ussurveyfoot": .usSurveyFoot
        case "foot", "internationalfoot": .internationalFoot
        case "meter", "metre": .meter
        default: .unknown
        }
        let directionUnit = unitsNode?.attributes["directionUnit"]?.lowercased() ?? "radians"
        let parser = LandXMLAlignmentParser(options: options, directionUnit: directionUnit)
        var alignments: [Alignment] = []
        for collection in root.children where collection.name == "Alignments" {
            for node in collection.children where node.name == "Alignment" { alignments.append(try parser.parse(node)) }
        }
        guard !alignments.isEmpty else { throw LandXMLParsingError.missingAlignment }
        var warnings: [String] = []
        if unit == .unknown { warnings.append("Unknown or unsupported linear unit; coordinates and lengths retained without conversion.") }
        for name in ["Surfaces", "CgPoints", "Parcels", "PipeNetworks"] where root.child(name) != nil {
            warnings.append("\(name) data is outside Phase 1 horizontal alignment scope and was not imported.")
        }
        return Project(name: root.child("Project")?.attributes["name"] ?? sourceName, unit: unit, alignments: alignments,
            coordinateSystemDescription: root.child("CoordinateSystem")?.attributes["desc"] ?? root.child("CoordinateSystem")?.attributes["name"], warnings: warnings)
    }
}
