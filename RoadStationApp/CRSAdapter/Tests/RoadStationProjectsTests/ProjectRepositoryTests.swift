import Foundation
import XCTest
import SwiftData
import RoadStationCore
import RoadStationFieldPosition
@testable import RoadStationProjects

private actor FaultFileStore: ProjectFileStoring {
    enum Fault: Sendable { case none, prepare, read, quarantine, purge }
    let base: ProjectFileStore
    var fault: Fault
    init(root: URL, fault: Fault) { base = ProjectFileStore(root: root); self.fault = fault }
    func set(_ fault: Fault) { self.fault = fault }
    func prepare(url: URL, projectID: UUID) async throws -> PreparedProjectSource {
        if fault == .prepare { throw ProjectStorageError.file("Injected copy failure") }
        return try await base.prepare(url: url, projectID: projectID)
    }
    func read(_ record: SavedProjectRecord) async throws -> ParsedProjectSource {
        if fault == .read { throw ProjectStorageError.file("Injected unreadable source") }
        return try await base.read(record)
    }
    func discard(_ source: PreparedProjectSource) async throws { try await base.discard(source) }
    func quarantine(projectID: UUID) async throws -> String? {
        if fault == .quarantine { throw ProjectStorageError.file("Injected deletion failure") }
        return try await base.quarantine(projectID: projectID)
    }
    func restoreQuarantine(_ name: String) async throws { try await base.restoreQuarantine(name) }
    func purgeQuarantine(_ name: String) async throws {
        if fault == .purge { throw ProjectStorageError.file("Injected cleanup failure") }
        try await base.purgeQuarantine(name)
    }
    func reconcile(_ records: [SavedProjectRecord]) async throws { try await base.reconcile(records) }
}
final class ProjectRepositoryTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadStationProjectsTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func xml(names: [String] = ["FIRST", "SECOND"], ids: Bool = false, epsg: Int? = nil) -> Data {
        let alignments = names.map { name in
            "<Alignment name=\"\(name)\" \(ids ? "oID=\"id-\(name)\"" : "") staStart=\"500\"><CoordGeom><Line><Start>0 0</Start><End>0 100</End></Line></CoordGeom></Alignment>"
        }.joined()
        return Data("<LandXML version=\"1.2\"><Project name=\"Test Project\"/><Units><Metric linearUnit=\"meter\"/></Units>\(epsg.map { "<CoordinateSystem epsgCode=\"\($0)\"/>" } ?? "")<Alignments>\(alignments)</Alignments></LandXML>".utf8)
    }
    private func source(_ root: URL, data: Data? = nil, name: String = "original.xml") throws -> URL {
        let url = root.appendingPathComponent(name); try (data ?? xml()).write(to: url); return url
    }
    private func cleanup(_ root: URL) { try? FileManager.default.removeItem(at: root) }
    @MainActor private func fails(_ block: () async throws -> Void, containing: String? = nil) async {
        do { try await block(); XCTFail("Expected a failure") }
        catch { if let containing { XCTAssertTrue(error.localizedDescription.contains(containing), error.localizedDescription) } }
    }
    @MainActor private func choices(_ repo: ProjectRepository, snapshot: OpenedProjectSnapshot,
        epsg: Int = 3857, provenance: CRSSelectionProvenance = .manual, index: Int = 1) async throws {
        let token = UUID(); await repo.beginChoiceSession(snapshot.saved.id, token: token)
        try await repo.saveChoices(snapshot.saved.id, sourcePath: snapshot.saved.sourceRelativePath, token: token, sequence: 1,
            epsg: epsg, provenance: provenance, alignmentIdentity: SavedAlignmentIdentity.key(for: snapshot.project.alignments[index]))
    }
    @MainActor func testCreatePreservesBytesAndMultipleAlignmentsWithoutExternalSource() async throws {
        let root = try root(); defer { cleanup(root) }
        let data = xml(), external = try source(root, data: data)
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: external)
        let records = try await repo.listProjects(); XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first); XCTAssertEqual(record.id, id); XCTAssertEqual(record.alignmentCount, 2)
        XCTAssertEqual(record.unit, .meter); XCTAssertNil(record.confirmedEPSG)
        let owned = root.appendingPathComponent("Projects/" + record.sourceRelativePath)
        XCTAssertEqual(try Data(contentsOf: owned), data); XCTAssertEqual(record.sourceSHA256.count, 64)
        try FileManager.default.removeItem(at: external)
        let reopened = try await repo.openProject(id)
        XCTAssertEqual(reopened.project.alignments.map(\.name), ["FIRST", "SECOND"])
        XCTAssertEqual(reopened.project.alignments[1].totalGeometricLength, 100)
        XCTAssertEqual(reopened.project.alignments[1].startStation, 500)
    }
    @MainActor func testDiskColdStartRestoresConfirmedCRSProvenanceAndNonFirstAlignment() async throws {
        for provenance in [CRSSelectionProvenance.landXML, .manual, .catalog] {
            let root = try root(); defer { cleanup(root) }
            var first: ProjectRepository? = try await ProjectRepository.make(root: root)
            let id = try await first!.createProject(source: source(root, data: xml(epsg: 3857)))
            let original = try await first!.openProject(id)
            try await choices(first!, snapshot: original, provenance: provenance)
            first = nil
            let cold = try await ProjectRepository.make(root: root)
            let list = try await cold.listProjects(); XCTAssertEqual(list.count, 1)
            let snapshot = try await cold.openProject(id)
            XCTAssertEqual(snapshot.selectedAlignment?.name, "SECOND")
            XCTAssertNotEqual(snapshot.selectedAlignment?.id, original.project.alignments[1].id, "Parser must rebuild ephemeral UUIDs")
            guard case .ready(let confirmed) = snapshot.crs else { return XCTFail("CRS must validate on reopen") }
            XCTAssertEqual(confirmed.definition.crs.epsgCode, 3857); XCTAssertEqual(confirmed.provenance, provenance)
            XCTAssertEqual(confirmed.definition.outputUnit, .linear(.meter))
            XCTAssertNotNil(snapshot.saved.lastOpenedAt)
        }
    }
    @MainActor func testRenamePersistsWithoutRenamingSource() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root)
        let id = try await repo.createProject(source: source(root))
        let before = try await repo.openProject(id)
        try await repo.renameProject(id, name: "  Renamed  ")
        let cold = try await ProjectRepository.make(root: root), after = try await cold.openProject(id)
        XCTAssertEqual(after.saved.displayName, "Renamed")
        XCTAssertEqual(after.saved.sourceFileName, "original.xml"); XCTAssertEqual(after.saved.sourceRelativePath, before.saved.sourceRelativePath)
        XCTAssertEqual(after.saved.sourceSHA256, before.saved.sourceSHA256)
    }
    @MainActor func testDeleteRemovesMetadataDirectoryAndFutureOwnedFiles() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root))
        let folder = root.appendingPathComponent("Projects/\(id.uuidString)")
        try Data("future-owned-file".utf8).write(to: folder.appendingPathComponent("future-placeholder.txt"))
        try await repo.deleteProject(id)
        let records = try await repo.listProjects(); XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/.Trash").path).count, 0)
    }
    @MainActor func testReplacementKeepsUUIDNameCRSAndRestoresByNameDespiteReordering() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root, data: xml(epsg: 3857)))
        let original = try await repo.openProject(id); try await choices(repo, snapshot: original)
        try await repo.renameProject(id, name: "Keep Name")
        let snapshot = try await repo.replaceSource(id, source: source(root, data: xml(names: ["SECOND", "FIRST", "THIRD"], epsg: 32631), name: "replacement.landxml"))
        XCTAssertEqual(snapshot.saved.id, id); XCTAssertEqual(snapshot.saved.displayName, "Keep Name")
        XCTAssertEqual(snapshot.selectedAlignment?.name, "SECOND"); XCTAssertEqual(snapshot.project.alignments.first?.name, "SECOND")
        XCTAssertEqual(snapshot.saved.sourceFileName, "replacement.landxml"); XCTAssertNotEqual(snapshot.saved.sourceRelativePath, original.saved.sourceRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/" + original.saved.sourceRelativePath).path))
        guard case .ready(let confirmed) = snapshot.crs else { return XCTFail("Keep saved CRS") }
        XCTAssertEqual(confirmed.definition.crs.epsgCode, 3857); XCTAssertEqual(confirmed.provenance, .manual)
        XCTAssertTrue(snapshot.warnings.contains { $0.contains("differs from imported") })
    }
    @MainActor func testSourceIDRestoresAfterRenameAndReordering() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root, data: xml(ids: true)))
        let original = try await repo.openProject(id); try await choices(repo, snapshot: original)
        let modified = String(decoding: xml(names: ["SECOND", "FIRST"], ids: true), as: UTF8.self).replacingOccurrences(of: "name=\"SECOND\"", with: "name=\"RENAMED\"")
        let snapshot = try await repo.replaceSource(id, source: source(root, data: Data(modified.utf8), name: "new.xml"))
        XCTAssertEqual(snapshot.selectedAlignment?.name, "RENAMED")
    }
    @MainActor func testMissingOrAmbiguousAlignmentNeverBindsByIndex() async throws {
        for names in [["FIRST", "OTHER"], ["SECOND", "SECOND"]] {
            let root = try root(); defer { cleanup(root) }
            let repo = try await ProjectRepository.make(root: root, inMemory: true)
            let id = try await repo.createProject(source: source(root))
            try await choices(repo, snapshot: repo.openProject(id))
            let snapshot = try await repo.replaceSource(id, source: source(root, data: xml(names: names), name: "new.xml"))
            XCTAssertNil(snapshot.selectedAlignment)
            XCTAssertTrue(snapshot.warnings.contains { $0.contains("previous alignment is unavailable or ambiguous") })
        }
    }
    @MainActor func testInvalidReplacementLeavesOriginalSourceAndMetadataIntact() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        await fails({ _ = try await repo.replaceSource(id, source: self.source(root, data: Data("<bad>".utf8), name: "bad.xml")) }, containing: "could not be parsed")
        let reopened = try await repo.openProject(id)
        XCTAssertEqual(reopened.saved.sourceRelativePath, original.saved.sourceRelativePath)
        XCTAssertEqual(reopened.saved.sourceSHA256, original.saved.sourceSHA256)
        XCTAssertEqual(reopened.project.alignments.map(\.name), ["FIRST", "SECOND"])
    }
    @MainActor func testInvalidCreateAndInjectedCopyFailureDoNotLeaveProjects() async throws {
        let root = try root(); defer { cleanup(root) }
        let files = FaultFileStore(root: root, fault: .none)
        let repo = try await ProjectRepository.make(root: root, inMemory: true, files: files)
        await fails({ _ = try await repo.createProject(source: self.source(root, data: Data("<bad>".utf8))) }, containing: "could not be parsed")
        await files.set(.prepare)
        await fails({ _ = try await repo.createProject(source: self.source(root)) }, containing: "copy failure")
        let records = try await repo.listProjects(); XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path).isEmpty)
    }
    @MainActor func testMetadataCommitFailureCleansCreateAndRollsBackReplacementAndDeletion() async throws {
        let root = try root(); defer { cleanup(root) }
        let failingCreate = try await ProjectRepository.make(root: root, inMemory: true, commitValidator: { throw ProjectStorageError.metadata("Injected commit failure") })
        await fails({ _ = try await failingCreate.createProject(source: self.source(root)) })
        let empty = try await failingCreate.listProjects(); XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects").path).isEmpty)
        let working = try await ProjectRepository.make(root: root)
        let id = try await working.createProject(source: source(root)), original = try await working.openProject(id)
        let failing = try await ProjectRepository.make(root: root, commitValidator: { throw ProjectStorageError.metadata("Injected commit failure") })
        await fails({ _ = try await failing.replaceSource(id, source: self.source(root, data: self.xml(names: ["NEW"]), name: "new.xml")) })
        await fails({ try await failing.deleteProject(id) })
        let cold = try await ProjectRepository.make(root: root), reopened = try await cold.openProject(id)
        XCTAssertEqual(reopened.saved.sourceRelativePath, original.saved.sourceRelativePath)
        XCTAssertEqual(reopened.project.alignments.count, 2)
    }
    @MainActor func testMissingCorruptUnreadableAndUnsafeSourcesRemainListedAndRecoverable() async throws {
        for failure in ["missing", "corrupt", "unreadable", "directory"] {
            let root = try root(); defer { cleanup(root) }
            let files = FaultFileStore(root: root, fault: .none)
            let repo = try await ProjectRepository.make(root: root, inMemory: true, files: files)
            let id = try await repo.createProject(source: source(root)), before = try await repo.openProject(id)
            let owned = root.appendingPathComponent("Projects/" + before.saved.sourceRelativePath)
            switch failure {
            case "missing": try FileManager.default.removeItem(at: owned)
            case "directory": try FileManager.default.removeItem(at: owned.deletingLastPathComponent().deletingLastPathComponent())
            case "corrupt": try Data("<broken>".utf8).write(to: owned)
            default: await files.set(.read)
            }
            await fails({ _ = try await repo.openProject(id) })
            let records = try await repo.listProjects(); XCTAssertEqual(records.count, 1)
            await files.set(.none)
            let recovered = try await repo.replaceSource(id, source: source(root, name: "recover.xml"))
            XCTAssertEqual(recovered.project.alignments.count, 2); XCTAssertEqual(recovered.saved.id, id)
        }
    }
    @MainActor func testInvalidAndUnsupportedPersistedEPSGRemainActionableWithoutReplacement() async throws {
        for code in [-1, 999999, 4326] {
            let root = try root(); defer { cleanup(root) }
            let repo = try await ProjectRepository.make(root: root, inMemory: true)
            let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
            try await choices(repo, snapshot: original, epsg: code)
            let reopened = try await repo.openProject(id)
            guard case .unavailable(let message) = reopened.crs else { return XCTFail("Invalid saved CRS cannot silently change") }
            XCTAssertTrue(message.contains("EPSG:\(code)")); XCTAssertEqual(reopened.saved.confirmedEPSG, code)
            XCTAssertEqual(reopened.selectedAlignment?.name, "SECOND")
        }
    }
    @MainActor func testDeletionFilesystemFailureKeepsMetadataAndDeferredPurgeCanRecover() async throws {
        let root = try root(); defer { cleanup(root) }
        let files = FaultFileStore(root: root, fault: .none)
        let repo = try await ProjectRepository.make(root: root, inMemory: true, files: files)
        let id = try await repo.createProject(source: source(root))
        await files.set(.quarantine); await fails { try await repo.deleteProject(id) }
        var records = try await repo.listProjects(); XCTAssertEqual(records.count, 1)
        await files.set(.purge); try await repo.deleteProject(id)
        records = try await repo.listProjects(); XCTAssertTrue(records.isEmpty)
        let warning = await repo.maintenanceWarning; XCTAssertNotNil(warning)
        await files.set(.none); try await repo.retryCleanup()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Projects/.Trash").path).isEmpty)
    }
    @MainActor func testInterruptedDeletionAndOrphanRevisionsRecoverOnColdStart() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        let files = ProjectFileStore(root: root)
        _ = try await files.quarantine(projectID: id) // Crash before metadata commit.
        let cold = try await ProjectRepository.make(root: root)
        let restored = try await cold.openProject(id); XCTAssertEqual(restored.saved.sourceSHA256, original.saved.sourceSHA256)
        let orphan = try await files.prepare(url: source(root), projectID: UUID())
        let unusedRevision = try await files.prepare(url: source(root), projectID: id)
        let newer = try await ProjectRepository.make(root: root)
        _ = try await newer.openProject(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/" + orphan.relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/" + unusedRevision.relativePath).path))
    }
    @MainActor func testStaleChoiceWritesCannotOverwriteNewerSessionOrSource() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        let old = UUID(), current = UUID(); await repo.beginChoiceSession(id, token: old); await repo.beginChoiceSession(id, token: current)
        try await repo.saveChoices(id, sourcePath: original.saved.sourceRelativePath, token: current, sequence: 2, epsg: 3857, provenance: .manual, alignmentIdentity: nil)
        try await repo.saveChoices(id, sourcePath: original.saved.sourceRelativePath, token: current, sequence: 1, epsg: 32631, provenance: .manual, alignmentIdentity: nil)
        try await repo.saveChoices(id, sourcePath: original.saved.sourceRelativePath, token: old, sequence: 3, epsg: 32631, provenance: .manual, alignmentIdentity: nil)
        var snapshot = try await repo.openProject(id); XCTAssertEqual(snapshot.saved.confirmedEPSG, 3857)
        snapshot = try await repo.replaceSource(id, source: source(root, name: "new.xml"))
        await repo.beginChoiceSession(id, token: current)
        try await repo.saveChoices(id, sourcePath: original.saved.sourceRelativePath, token: current, sequence: 4, epsg: 32631, provenance: .manual, alignmentIdentity: nil)
        let final = try await repo.openProject(id); XCTAssertEqual(final.saved.confirmedEPSG, 3857)
    }
    @MainActor func testDirectoryUnavailableAndDatabaseFailureAreActionable() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Projects"))
        try Data("not a folder".utf8).write(to: root.appendingPathComponent("Projects"))
        await fails({ _ = try await repo.createProject(source: self.source(root)) })
        let records = try await repo.listProjects(); XCTAssertTrue(records.isEmpty)
        let blockedRoot = try source(root, data: Data("not a directory".utf8), name: "blocked")
        await fails({ _ = try await ProjectRepository.make(root: blockedRoot) }, containing: "metadata")
    }
    @MainActor func testUnexpectedValidSourceChangeIsNotSilentlyAccepted() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        try xml(names: ["OTHER"]).write(to: root.appendingPathComponent("Projects/" + original.saved.sourceRelativePath))
        await fails({ _ = try await repo.openProject(id) }, containing: "changed unexpectedly")
    }
    @MainActor func testKnownRealORDSourceReopensThroughValidatedParserAndMeasuresPerformance() async throws {
        let root = try root(); defer { cleanup(root) }
        let fixture = Bundle(for: type(of: self)).url(forResource: "CROSSGATES", withExtension: "xml") ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../Validation/RealORD/CROSSGATES/CROSSGATES.xml").standardizedFileURL
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Real ORD source is available in repository-hosted tests") }
        let repo = try await ProjectRepository.make(root: root, inMemory: true)
        let id = try await repo.createProject(source: fixture)
        let start = Date(), records = try await repo.listProjects(), listMS = Date().timeIntervalSince(start) * 1000
        let snapshot = try await repo.openProject(id)
        let independent = try LandXMLParser().parse(url: fixture)
        XCTAssertEqual(records.count, 1); XCTAssertEqual(snapshot.project.alignments.count, independent.alignments.count)
        XCTAssertEqual(snapshot.project.alignments.map(\.totalGeometricLength), independent.alignments.map(\.totalGeometricLength))
        XCTAssertEqual(snapshot.project.unit, .usSurveyFoot)
        print("Saved projects performance: list \(listMS) ms; CROSSGATES XML+hash \(snapshot.parseMilliseconds) ms; repository open \(snapshot.openMilliseconds) ms")
    }
    @MainActor func testDistinctFootUnitsAndLegitimateDuplicateImportsPersist() async throws {
        for (xmlUnit, unit) in [("Foot", ProjectUnit.internationalFoot), ("USSurveyFoot", .usSurveyFoot)] {
            let root = try root(); defer { cleanup(root) }
            let data = Data(String(decoding: xml(), as: UTF8.self).replacingOccurrences(of: "linearUnit=\"meter\"", with: "linearUnit=\"\(xmlUnit)\"").utf8)
            let repo = try await ProjectRepository.make(root: root)
            let input = try source(root, data: data), id = try await repo.createProject(source: input)
            let original = try await repo.openProject(id); try await choices(repo, snapshot: original)
            let duplicate = try await repo.createProject(source: input); XCTAssertNotEqual(duplicate, id)
            let cold = try await ProjectRepository.make(root: root), restored = try await cold.openProject(id)
            let records = try await cold.listProjects(); XCTAssertEqual(records.count, 2)
            XCTAssertEqual(restored.project.unit, unit); XCTAssertEqual(restored.saved.unit, unit)
            guard case .ready(let crs) = restored.crs else { return XCTFail("Foot output CRS should restore") }
            XCTAssertEqual(crs.definition.outputUnit, .linear(unit))
        }
    }
    @MainActor func testUnknownProvenanceAndUnsafeMetadataNeverInferCRSOrDeleteSource() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        let context = ModelContext(repo.modelContainer)
        let raw = try XCTUnwrap(context.fetch(FetchDescriptor<SavedProject>()).first)
        raw.confirmedEPSG = 3857; raw.provenanceRawValue = "unknown future provenance"; try context.save()
        let cold = try await ProjectRepository.make(root: root), snapshot = try await cold.openProject(id)
        guard case .unavailable(let message) = snapshot.crs else { return XCTFail("Unknown provenance cannot confirm") }
        XCTAssertTrue(message.contains("unknown provenance"))
        raw.sourceRelativePath = "../../original.xml"; try context.save()
        let corrupt = try await ProjectRepository.make(root: root)
        await fails({ _ = try await corrupt.openProject(id) }, containing: "path is invalid")
        let records = try await corrupt.listProjects(); XCTAssertEqual(records.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/" + original.saved.sourceRelativePath).path))
    }

    @MainActor func testMissingMetadataStoreNeverDeletesOwnedEngineeringSource() async throws {
        let root = try root(); defer { cleanup(root) }
        let repo = try await ProjectRepository.make(root: root)
        let id = try await repo.createProject(source: source(root)), original = try await repo.openProject(id)
        try FileManager.default.removeItem(at: root.appendingPathComponent("projects.store"))
        await fails({ _ = try await ProjectRepository.make(root: root) }, containing: "metadata store is missing")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Projects/" + original.saved.sourceRelativePath).path))
    }

}
