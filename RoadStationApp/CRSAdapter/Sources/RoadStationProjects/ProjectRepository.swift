import Foundation
import SwiftData
import RoadStationCore
import RoadStationAppleCRS
import RoadStationFieldPosition

/// SwiftData's serial model executor owns every model/context access. File IO,
/// parsing and PROJ validation never execute on MainActor.
@ModelActor public actor ProjectRepository {
    private var files: (any ProjectFileStoring)?
    private var commitValidator: @Sendable () throws -> Void = {}
    private var busyIDs: Set<UUID> = []
    private var cleanupInProgress = false
    private var choiceSessions: [UUID: (UUID, Int)] = [:]
    public private(set) var maintenanceWarning: String?

    public static func make(root: URL, inMemory: Bool = false,
        files: (any ProjectFileStoring)? = nil,
        commitValidator: @escaping @Sendable () throws -> Void = {}) async throws -> ProjectRepository {
        try await Task.detached(priority: .userInitiated) {
            do {
                try FileManager().createDirectory(at: root, withIntermediateDirectories: true)
                let fm = FileManager(), storeURL = root.appendingPathComponent("projects.store")
                let projectDirectory = root.appendingPathComponent("Projects")
                if !inMemory, !fm.fileExists(atPath: storeURL.path), fm.fileExists(atPath: projectDirectory.path) {
                    let folders = try fm.contentsOfDirectory(at: projectDirectory, includingPropertiesForKeys: nil)
                    let owned = folders.contains { UUID(uuidString: $0.lastPathComponent) != nil }
                    let trash = projectDirectory.appendingPathComponent(".Trash")
                    let pendingDeletion = (try? fm.contentsOfDirectory(atPath: trash.path).isEmpty) == false
                    guard !owned, !pendingDeletion else {
                        throw ProjectStorageError.metadata("The metadata store is missing. Project files were retained. Restore a device backup or recover the store before retrying")
                    }
                }
                let schema = Schema(versionedSchema: ProjectsSchemaV1.self)
                let configuration = inMemory ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) :
                    ModelConfiguration(schema: schema, url: root.appendingPathComponent("projects.store"), cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, migrationPlan: ProjectsMigrationPlan.self, configurations: [configuration])
                let repository = ProjectRepository(modelContainer: container)
                try await repository.configure(files: files ?? ProjectFileStore(root: root), commitValidator: commitValidator)
                return repository
            } catch { throw ProjectStorageError.metadata(error.localizedDescription) }
        }.value
    }
    private func configure(files: any ProjectFileStoring, commitValidator: @escaping @Sendable () throws -> Void) async throws {
        self.files = files; self.commitValidator = commitValidator; modelContext.autosaveEnabled = false
        // A metadata failure must never cause orphan reconciliation against an empty list.
        let records = try listProjects()
        do { try await files.reconcile(records) } catch { maintenanceWarning = "Project file cleanup needs retry: \(error.localizedDescription)" }
    }
    private func store() throws -> any ProjectFileStoring {
        guard let files else { throw ProjectStorageError.file("Project file service is unavailable") }
        return files
    }
    private func lock(_ id: UUID) throws {
        guard !cleanupInProgress, busyIDs.insert(id).inserted else { throw ProjectStorageError.busy }
    }
    private func fetch(_ id: UUID) throws -> SavedProject {
        let descriptor = FetchDescriptor<SavedProject>(predicate: #Predicate { $0.id == id })
        guard let value = try modelContext.fetch(descriptor).first else { throw ProjectStorageError.notFound }
        return value
    }
    private func commit() throws {
        do { try commitValidator(); try modelContext.save() }
        catch { modelContext.rollback(); throw ProjectStorageError.metadata(error.localizedDescription) }
    }
    public func listProjects() throws -> [SavedProjectRecord] {
        do {
            return try modelContext.fetch(FetchDescriptor<SavedProject>()).map(\.record).sorted {
                let a = $0.lastOpenedAt ?? $0.createdAt, b = $1.lastOpenedAt ?? $1.createdAt
                return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
            }
        } catch { throw ProjectStorageError.metadata(error.localizedDescription) }
    }
    public func createProject(source: URL, now: Date = Date()) async throws -> UUID {
        let id = UUID(), files = try store()
        try lock(id); defer { busyIDs.remove(id) }
        let staged = try await files.prepare(url: source, projectID: id)
        let record = SavedProjectRecord(id: id, displayName: staged.project.name, sourceFileName: staged.originalName,
            sourceRelativePath: staged.relativePath, sourceUpdatedAt: now, sourceSHA256: staged.hash, createdAt: now, updatedAt: now,
            lastOpenedAt: nil, unitRawValue: staged.project.unit.rawValue, alignmentCount: staged.project.alignments.count,
            confirmedEPSG: nil, provenanceRawValue: nil, selectedAlignmentIdentity: nil)
        modelContext.insert(SavedProject(record: record))
        do { try commit() }
        catch {
            do { try await files.discard(staged) } catch { maintenanceWarning = "Failed import files need cleanup: \(error.localizedDescription)" }
            throw error
        }
        return id
    }
    private func snapshot(record: SavedProjectRecord, parsed: ParsedProjectSource, started: Date) -> OpenedProjectSnapshot {
        var warnings: [String] = []
        let selected = SavedAlignmentIdentity.resolve(record.selectedAlignmentIdentity, in: parsed.project)
        if record.selectedAlignmentIdentity != nil, selected == nil {
            warnings.append("The previous alignment is unavailable or ambiguous. Select an alignment to continue.")
        }
        if record.unit != parsed.project.unit { warnings.append("Saved unit metadata differs from LandXML. Parsed source units are authoritative.") }
        let crs: SavedCRSState
        if let code = record.confirmedEPSG {
            if let provenance = record.provenance {
                do {
                    let definition = try PROJProjectCoordinateTransformer(resolution: .identified(CoordinateReferenceSystem(epsgCode: code)), outputUnit: .linear(parsed.project.unit)).definition
                    crs = .ready(ConfirmedProjectCRS(definition: definition, provenance: provenance))
                } catch { crs = .unavailable("Saved CRS EPSG:\(code) is unavailable: \(error.localizedDescription). Choose and confirm another CRS.") }
            } else { crs = .unavailable("Saved CRS EPSG:\(code) has unknown provenance. Choose and confirm a CRS.") }
            if case .identified(let imported) = parsed.project.crsResolution, imported.epsgCode != code {
                warnings.append("Saved confirmed EPSG:\(code) differs from imported \(imported.identifier). The saved user confirmation is retained.")
            }
        } else { crs = .unconfirmed }
        return OpenedProjectSnapshot(saved: record, project: parsed.project, selectedAlignment: selected, crs: crs,
            warnings: warnings, parseMilliseconds: parsed.parseMilliseconds, openMilliseconds: Date().timeIntervalSince(started) * 1000)
    }
    public func openProject(_ id: UUID, now: Date = Date()) async throws -> OpenedProjectSnapshot {
        try lock(id); defer { busyIDs.remove(id) }
        let started = Date(), record = try fetch(id).record
        let parsed = try await store().read(record)
        let model = try fetch(id); model.lastOpenedAt = now
        try commit()
        return snapshot(record: model.record, parsed: parsed, started: started)
    }
    public func renameProject(_ id: UUID, name: String, now: Date = Date()) throws {
        try lock(id); defer { busyIDs.remove(id) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProjectStorageError.metadata("Enter a project name") }
        let model = try fetch(id); model.displayName = name; model.updatedAt = now; try commit()
    }
    public func beginChoiceSession(_ id: UUID, token: UUID) { choiceSessions[id] = (token, 0) }
    /// Source pointer and session/sequence guards keep old async saves from writing
    /// choices into a replacement source or a newer opened session.
    public func saveChoices(_ id: UUID, sourcePath: String, token: UUID, sequence: Int,
        epsg: Int?, provenance: CRSSelectionProvenance?, alignmentIdentity: String?, now: Date = Date()) throws {
        guard let session = choiceSessions[id], session.0 == token, sequence > session.1 else { return }
        try lock(id); defer { busyIDs.remove(id) }
        let model = try fetch(id)
        guard model.sourceRelativePath == sourcePath else { return }
        if let epsg, let provenance { model.confirmedEPSG = epsg; model.provenanceRawValue = SavedProjectRecord.provenanceKey(provenance) }
        if let alignmentIdentity { model.selectedAlignmentIdentity = alignmentIdentity }
        model.updatedAt = now; try commit(); choiceSessions[id] = (token, sequence)
    }
    public func replaceSource(_ id: UUID, source: URL, now: Date = Date()) async throws -> OpenedProjectSnapshot {
        try lock(id); defer { busyIDs.remove(id) }
        let started = Date(), original = try fetch(id).record, files = try store()
        let staged = try await files.prepare(url: source, projectID: id)
        let model = try fetch(id)
        model.sourceFileName = staged.originalName; model.sourceRelativePath = staged.relativePath
        model.sourceUpdatedAt = now; model.sourceSHA256 = staged.hash; model.unitRawValue = staged.project.unit.rawValue
        model.alignmentCount = staged.project.alignments.count; model.updatedAt = now; model.lastOpenedAt = now
        do { try commit() }
        catch {
            do { try await files.discard(staged) } catch { maintenanceWarning = "Replacement files need cleanup: \(error.localizedDescription)" }
            throw error
        }
        choiceSessions[id] = nil
        do {
            try await files.discard(PreparedProjectSource(projectID: id, relativePath: original.sourceRelativePath,
                originalName: original.sourceFileName, hash: original.sourceSHA256, project: staged.project, parseMilliseconds: 0))
        } catch { maintenanceWarning = "Source replaced; old files need cleanup: \(error.localizedDescription)" }
        let parsed = ParsedProjectSource(project: staged.project, hash: staged.hash, parseMilliseconds: staged.parseMilliseconds)
        let opened = snapshot(record: model.record, parsed: parsed, started: started)
        return OpenedProjectSnapshot(saved: opened.saved, project: opened.project, selectedAlignment: opened.selectedAlignment,
            crs: opened.crs, warnings: opened.warnings + ["Source LandXML was replaced. Review the parsed alignment collection and retained CRS confirmation."],
            parseMilliseconds: opened.parseMilliseconds, openMilliseconds: opened.openMilliseconds)
    }
    public func deleteProject(_ id: UUID) async throws {
        try lock(id); defer { busyIDs.remove(id) }
        let model = try fetch(id), files = try store()
        let quarantined = try await files.quarantine(projectID: id)
        modelContext.delete(model)
        do { try commit() }
        catch {
            if let quarantined {
                do { try await files.restoreQuarantine(quarantined) } catch { maintenanceWarning = "Deletion rollback needs file recovery: \(error.localizedDescription)" }
            }
            throw error
        }
        choiceSessions[id] = nil
        if let quarantined {
            do { try await files.purgeQuarantine(quarantined) }
            catch { maintenanceWarning = "Project removed; its files need cleanup: \(error.localizedDescription). Retry file cleanup." }
        }
    }
    public func retryCleanup() async throws {
        guard busyIDs.isEmpty, !cleanupInProgress else { throw ProjectStorageError.busy }
        cleanupInProgress = true; defer { cleanupInProgress = false }
        try await store().reconcile(try listProjects()); maintenanceWarning = nil
    }
}
