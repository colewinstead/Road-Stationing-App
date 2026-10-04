import Foundation
import SwiftData
import RoadStationCore
import RoadStationFieldPosition

public enum ProjectsSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [SavedProject.self] }
    @Model public final class SavedProject {
        @Attribute(.unique) public var id: UUID
        public var displayName: String
        public var sourceFileName: String
        public var sourceRelativePath: String
        public var sourceUpdatedAt: Date
        public var sourceSHA256: String
        public var createdAt: Date
        public var updatedAt: Date
        public var lastOpenedAt: Date?
        public var unitRawValue: String
        public var alignmentCount: Int
        public var confirmedEPSG: Int?
        public var provenanceRawValue: String?
        public var selectedAlignmentIdentity: String?
        public var modelVersion: Int
        public init(record: SavedProjectRecord) {
            id = record.id; displayName = record.displayName; sourceFileName = record.sourceFileName
            sourceRelativePath = record.sourceRelativePath; sourceSHA256 = record.sourceSHA256; sourceUpdatedAt = record.sourceUpdatedAt
            createdAt = record.createdAt; updatedAt = record.updatedAt; lastOpenedAt = record.lastOpenedAt
            unitRawValue = record.unitRawValue; alignmentCount = record.alignmentCount
            confirmedEPSG = record.confirmedEPSG; provenanceRawValue = record.provenanceRawValue
            selectedAlignmentIdentity = record.selectedAlignmentIdentity; modelVersion = 1
        }
        var record: SavedProjectRecord {
            SavedProjectRecord(id: id, displayName: displayName, sourceFileName: sourceFileName,
                sourceRelativePath: sourceRelativePath, sourceUpdatedAt: sourceUpdatedAt, sourceSHA256: sourceSHA256, createdAt: createdAt,
                updatedAt: updatedAt, lastOpenedAt: lastOpenedAt, unitRawValue: unitRawValue,
                alignmentCount: alignmentCount, confirmedEPSG: confirmedEPSG, provenanceRawValue: provenanceRawValue,
                selectedAlignmentIdentity: selectedAlignmentIdentity)
        }
    }
}
public typealias SavedProject = ProjectsSchemaV1.SavedProject
public enum ProjectsMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [ProjectsSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
/// The only metadata representation allowed to cross the persistence actor.
public struct SavedProjectRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var sourceFileName: String
    public var sourceRelativePath: String
    public var sourceUpdatedAt: Date
    public var sourceSHA256: String
    public let createdAt: Date
    public var updatedAt: Date
    public var lastOpenedAt: Date?
    public var unitRawValue: String
    public var alignmentCount: Int
    public var confirmedEPSG: Int?
    public var provenanceRawValue: String?
    public var selectedAlignmentIdentity: String?
    public var unit: ProjectUnit { ProjectUnit(rawValue: unitRawValue) ?? .unknown }
    public var provenance: CRSSelectionProvenance? {
        switch provenanceRawValue { case "landxml": .landXML; case "manual": .manual; case "catalog": .catalog; default: nil }
    }
    public static func provenanceKey(_ provenance: CRSSelectionProvenance) -> String {
        switch provenance { case .landXML: "landxml"; case .manual: "manual"; case .catalog: "catalog" }
    }
}
public enum SavedCRSState: Equatable, Sendable {
    case unconfirmed
    case ready(ConfirmedProjectCRS)
    case unavailable(String)
}
public struct OpenedProjectSnapshot: Sendable {
    public let saved: SavedProjectRecord
    public let project: Project
    public let selectedAlignment: Alignment?
    public let crs: SavedCRSState
    public let warnings: [String]
    public let parseMilliseconds: Double
    public let openMilliseconds: Double
}
/// Parser UUIDs are intentionally ephemeral. Source IDs survive name/order changes;
/// unique names are the fallback. Ambiguous identities never select an alignment.
public enum SavedAlignmentIdentity {
    public static func key(for alignment: Alignment) -> String {
        if let source = alignment.metadata.sourceIdentifier, !source.isEmpty {
            return "source:" + Data(source.utf8).base64EncodedString()
        }
        return "name:" + Data(alignment.name.utf8).base64EncodedString()
    }
    public static func resolve(_ key: String?, in project: Project) -> Alignment? {
        guard let key else { return nil }
        let matches = project.alignments.filter { self.key(for: $0) == key }
        return matches.count == 1 ? matches[0] : nil
    }
}
public enum ProjectStorageError: LocalizedError, Sendable {
    case missingSource, invalidPath, notFound, busy, sourceChanged, parsing(String), file(String), metadata(String)
    public var errorDescription: String? {
        switch self {
        case .missingSource: "Source LandXML is missing. Replace / re-import LandXML, or delete this project."
        case .invalidPath: "The saved source path is invalid. Replace / re-import LandXML to recover this project."
        case .notFound: "The saved project no longer exists. Reload Projects."
        case .busy: "Another project operation is in progress. Try again when it finishes."
        case .sourceChanged: "The saved source has changed unexpectedly. Replace / re-import LandXML to accept a new source."
        case .parsing(let detail): "LandXML could not be parsed: \(detail)"
        case .file(let detail): "Project files could not be accessed: \(detail). Check device storage and try again."
        case .metadata(let detail): "Saved project metadata could not be loaded or saved: \(detail). Retry without deleting app data."
        }
    }
}
