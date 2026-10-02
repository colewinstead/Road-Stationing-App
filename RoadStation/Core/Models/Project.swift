import Foundation

public enum ProjectUnit: String, Codable, Sendable {
    case usSurveyFoot, internationalFoot, meter, unknown
    public var symbol: String {
        switch self { case .meter: "m"; case .usSurveyFoot, .internationalFoot: "ft"; case .unknown: "units" }
    }
}

public struct Project: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let unit: ProjectUnit
    public let alignments: [Alignment]
    public let coordinateSystemDescription: String?
    public let warnings: [String]
    public init(id: UUID = UUID(), name: String, unit: ProjectUnit, alignments: [Alignment],
                coordinateSystemDescription: String? = nil, warnings: [String] = []) {
        self.id = id; self.name = name; self.unit = unit; self.alignments = alignments
        self.coordinateSystemDescription = coordinateSystemDescription; self.warnings = warnings
    }
}
