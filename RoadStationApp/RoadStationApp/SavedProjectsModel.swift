import Foundation
import SwiftUI
import Combine
import RoadStationCore
import RoadStationProjects
import RoadStationFieldPosition

struct OpenedProjectSession {
    var saved: SavedProjectRecord
    let project: Project
    let field: FieldPositionSession
    var warnings: [String]
    let parseMilliseconds: Double
    let openMilliseconds: Double
}
@MainActor
final class ProjectModel: ObservableObject {
    @Published private(set) var projects: [SavedProjectRecord] = []
    @Published private(set) var opened: OpenedProjectSession?
    @Published private(set) var isImporting = false
    @Published private(set) var openRevision = 0
    @Published private(set) var isSavingChoices = false
    @Published private(set) var choicesSaveError: String?
    private var pendingChoiceWrites = 0
    @Published var error: String?
    @Published private(set) var maintenanceWarning: String?
    @Published private(set) var listMilliseconds = 0.0
    private var repository: ProjectRepository?
    private var observation: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private var sequence = 0
    private var activeToken: UUID?

    func initialize() async {
        guard repository == nil, !isImporting else { return }
        isImporting = true; defer { isImporting = false }
        do {
            let root: URL
            #if DEBUG
            if let override = ProcessInfo.processInfo.environment["ROADSTATION_TEST_STORAGE"] {
                // UI-test isolation only. Release cannot redirect persistent storage.
                root = try ProjectFileStore.testingRoot(identifier: override)
            } else { root = try ProjectFileStore.applicationRoot() }
            #else
            root = try ProjectFileStore.applicationRoot()
            #endif
            repository = try await ProjectRepository.make(root: root)
            try await refreshList(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func refreshList() async throws {
        guard let repository else { return }
        let start = Date(); projects = try await repository.listProjects()
        listMilliseconds = Date().timeIntervalSince(start) * 1000
        maintenanceWarning = await repository.maintenanceWarning
        if var session = opened, let saved = projects.first(where: { $0.id == session.saved.id }) {
            session.saved = saved
            if SavedAlignmentIdentity.resolve(saved.selectedAlignmentIdentity, in: session.project) != nil {
                session.warnings.removeAll { $0.hasPrefix("The previous alignment") }
            }
            if session.field.confirmedCRS != nil { session.warnings.removeAll { $0.hasPrefix("Saved CRS EPSG:") } }
            session.warnings.removeAll { $0.hasPrefix("Saved confirmed EPSG:") }
            if let code = saved.confirmedEPSG, case .identified(let imported) = session.project.crsResolution, code != imported.epsgCode {
                session.warnings.append("Saved confirmed EPSG:\(code) differs from imported \(imported.identifier). The saved user confirmation is retained.")
            }
            opened = session
        }
    }
    func importFile(_ url: URL) {
        Task { await create(url) }
    }
    private func create(_ url: URL) async {
        guard !isImporting, let repository else { return }
        isImporting = true; error = nil; defer { isImporting = false }
        await saveTask?.value
        do {
            let id = try await repository.createProject(source: url)
            let snapshot = try await repository.openProject(id)
            await accept(snapshot); try await refreshList()
        } catch { self.error = error.localizedDescription; try? await refreshList() }
    }
    func open(_ id: UUID) async {
        guard !isImporting, let repository else { return }
        isImporting = true; error = nil; defer { isImporting = false }
        await saveTask?.value
        do { await accept(try await repository.openProject(id)); try await refreshList() }
        catch { self.error = error.localizedDescription }
    }
    private func accept(_ snapshot: OpenedProjectSnapshot) async {
        guard let repository else { return }
        let field = FieldPositionSession(service: CoreLocationService())
        field.load(project: snapshot.project)
        if let code = snapshot.saved.confirmedEPSG, let provenance = snapshot.saved.provenance {
            await field.restoreConfirmedCRS(code: code, provenance: provenance)
        }
        if let alignment = snapshot.selectedAlignment { await field.selectAlignment(alignment) }
        let token = UUID(), id = snapshot.saved.id, path = snapshot.saved.sourceRelativePath
        await repository.beginChoiceSession(id, token: token); activeToken = token
        observation?.cancel(); opened?.field.stop(); sequence = 0
        pendingChoiceWrites = 0; isSavingChoices = false; choicesSaveError = nil
        var warnings = snapshot.warnings
        if case .unavailable(let message) = snapshot.crs { warnings.append(message) }
        // Geometry, metadata, CRS and selection become visible together.
        opened = OpenedProjectSession(saved: snapshot.saved, project: snapshot.project, field: field,
            warnings: warnings, parseMilliseconds: snapshot.parseMilliseconds, openMilliseconds: snapshot.openMilliseconds)
        openRevision += 1
        observation = Publishers.CombineLatest(field.$confirmedCRS, field.$alignment).dropFirst().sink { [weak self] crs, alignment in
            guard let self else { return }
            self.sequence += 1; self.pendingChoiceWrites += 1; self.isSavingChoices = true; self.choicesSaveError = nil
            let sequence = self.sequence, previous = self.saveTask
            self.saveTask = Task { [weak self] in
                await previous?.value
                defer {
                    if self?.activeToken == token, let self {
                        self.pendingChoiceWrites -= 1; self.isSavingChoices = self.pendingChoiceWrites > 0
                    }
                }
                do {
                    try await repository.saveChoices(id, sourcePath: path, token: token, sequence: sequence,
                        epsg: crs?.definition.crs.epsgCode, provenance: crs?.provenance,
                        alignmentIdentity: alignment.map(SavedAlignmentIdentity.key(for:)))
                    guard self?.activeToken == token else { return }
                    try await self?.refreshList()
                    if self?.sequence == sequence { self?.choicesSaveError = nil }
                    if self?.error?.hasPrefix("Project changes could not be saved:") == true { self?.error = nil }
                } catch { self?.choicesSaveError = error.localizedDescription; self?.error = "Project changes could not be saved: \(error.localizedDescription)" }
            }
        }
    }
    func rename(_ id: UUID, name: String) async {
        guard !isImporting, let repository else { return }
        isImporting = true; defer { isImporting = false }; error = nil
        await saveTask?.value
        do { try await repository.renameProject(id, name: name); try await refreshList() }
        catch { self.error = error.localizedDescription }
    }
    func replace(_ id: UUID, source: URL) async {
        guard !isImporting, let repository else { return }
        isImporting = true; defer { isImporting = false }; error = nil
        await saveTask?.value
        do { await accept(try await repository.replaceSource(id, source: source)); try await refreshList() }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ id: UUID) async -> Bool {
        guard !isImporting, let repository else { return false }
        isImporting = true; defer { isImporting = false }; error = nil
        await saveTask?.value
        do {
            try await repository.deleteProject(id)
            if opened?.saved.id == id { observation?.cancel(); opened?.field.stop(); opened = nil }
            try await refreshList(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func retryCleanup() async {
        guard !isImporting, let repository else { return }
        isImporting = true; defer { isImporting = false }
        do { try await repository.retryCleanup(); try await refreshList() }
        catch { self.error = error.localizedDescription }
    }
    func reload() async {
        if repository == nil { await initialize(); return }
        guard !isImporting else { return }
        isImporting = true; defer { isImporting = false }
        do { try await refreshList(); error = nil } catch { self.error = error.localizedDescription }
    }
    func flushChoices() async { await saveTask?.value }
    func retrySave() async {
        guard !isImporting, let field = opened?.field else { return }
        // Republish choices through persistence only; never invalidate a live result.
        if let id = opened?.saved.id, let path = opened?.saved.sourceRelativePath, let repository {
            sequence += 1
            // The observer's active token is retained separately for explicit retries.
            guard let token = activeToken else { return }
            do {
                try await repository.saveChoices(id, sourcePath: path, token: token, sequence: sequence,
                    epsg: field.confirmedCRS?.definition.crs.epsgCode, provenance: field.confirmedCRS?.provenance,
                    alignmentIdentity: field.alignment.map(SavedAlignmentIdentity.key(for:)))
                try await refreshList(); error = nil; choicesSaveError = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    #if DEBUG
    func loadSample(_ sample: SampleFile) {
        guard let url = Bundle.main.url(forResource: sample.name, withExtension: "xml") else {
            error = "Bundled sample is missing: \(sample.name).xml"; return
        }
        importFile(url)
    }
    #endif
}
