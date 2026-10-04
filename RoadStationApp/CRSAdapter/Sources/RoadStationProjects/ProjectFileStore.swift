import Foundation
import CryptoKit
import RoadStationCore

public struct PreparedProjectSource: Sendable {
    public let projectID: UUID
    public let relativePath: String
    public let originalName: String
    public let hash: String
    public let project: Project
    public let parseMilliseconds: Double
}
public struct ParsedProjectSource: Sendable {
    public let project: Project
    public let hash: String
    public let parseMilliseconds: Double
}
public protocol ProjectFileStoring: Sendable {
    func prepare(url: URL, projectID: UUID) async throws -> PreparedProjectSource
    func read(_ record: SavedProjectRecord) async throws -> ParsedProjectSource
    func discard(_ source: PreparedProjectSource) async throws
    func quarantine(projectID: UUID) async throws -> String?
    func restoreQuarantine(_ name: String) async throws
    func purgeQuarantine(_ name: String) async throws
    func reconcile(_ records: [SavedProjectRecord]) async throws
}
/// All app-owned file IO and parsing execute on this actor, never on MainActor.
public actor ProjectFileStore: ProjectFileStoring {
    public let root: URL
    private let fm = FileManager()
    public init(root: URL) { self.root = root }
    public static func applicationRoot() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ProjectStorageError.file("Application Support is unavailable")
        }
        return support.appendingPathComponent("RoadStation", isDirectory: true)
    }
    #if DEBUG
    public static func testingRoot(identifier: String) throws -> URL {
        guard UUID(uuidString: identifier) != nil else { throw ProjectStorageError.invalidPath }
        return FileManager.default.temporaryDirectory.appendingPathComponent("RoadStationUITests").appendingPathComponent(identifier)
    }
    #endif
    private var projects: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    private var trash: URL { projects.appendingPathComponent(".Trash", isDirectory: true) }
    private func directory(_ id: UUID) -> URL { projects.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func sourceURL(_ path: String, id: UUID) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Substring(id.uuidString), parts[1] == "Sources",
              parts[2].hasSuffix(".landxml"), UUID(uuidString: String(parts[2].dropLast(8))) != nil else {
            throw ProjectStorageError.invalidPath
        }
        let url = projects.appendingPathComponent(path)
        for candidate in [directory(id), directory(id).appendingPathComponent("Sources"), url] {
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw ProjectStorageError.invalidPath
            }
        }
        return url
    }
    private func parse(_ data: Data, name: String) throws -> ParsedProjectSource {
        let start = Date()
        let project: Project
        do { project = try LandXMLParser().parse(data: data, sourceName: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent) }
        catch { throw ProjectStorageError.parsing(error.localizedDescription) }
        return ParsedProjectSource(project: project, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            parseMilliseconds: Date().timeIntervalSince(start) * 1000)
    }
    public func prepare(url: URL, projectID: UUID) throws -> PreparedProjectSource {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ProjectStorageError.file(error.localizedDescription) }
        let parsed = try parse(data, name: url.lastPathComponent)
        let path = "\(projectID.uuidString)/Sources/\(UUID().uuidString).landxml"
        let target = try sourceURL(path, id: projectID)
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            // Remove incomplete first-import directories; preserve existing sources.
            try? fm.removeItem(at: target)
            if (try? fm.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).isEmpty) == true {
                try? fm.removeItem(at: target.deletingLastPathComponent())
                if (try? fm.contentsOfDirectory(atPath: directory(projectID).path).isEmpty) == true { try? fm.removeItem(at: directory(projectID)) }
            }
            throw ProjectStorageError.file(error.localizedDescription)
        }
        return PreparedProjectSource(projectID: projectID, relativePath: path, originalName: url.lastPathComponent,
            hash: parsed.hash, project: parsed.project, parseMilliseconds: parsed.parseMilliseconds)
    }
    public func read(_ record: SavedProjectRecord) throws -> ParsedProjectSource {
        let url = try sourceURL(record.sourceRelativePath, id: record.id)
        guard fm.fileExists(atPath: url.path) else { throw ProjectStorageError.missingSource }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ProjectStorageError.file(error.localizedDescription) }
        let parsed = try parse(data, name: record.sourceFileName)
        guard parsed.hash == record.sourceSHA256 else { throw ProjectStorageError.sourceChanged }
        return parsed
    }
    public func discard(_ source: PreparedProjectSource) throws {
        let url = try sourceURL(source.relativePath, id: source.projectID)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        if (try? fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).isEmpty) == true {
            try fm.removeItem(at: url.deletingLastPathComponent())
            if (try? fm.contentsOfDirectory(atPath: directory(source.projectID).path).isEmpty) == true { try fm.removeItem(at: directory(source.projectID)) }
        }
    }
    public func quarantine(projectID: UUID) throws -> String? {
        let source = directory(projectID)
        guard fm.fileExists(atPath: source.path) else { return nil }
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let name = "\(projectID.uuidString)-\(UUID().uuidString)"
        try fm.moveItem(at: source, to: trash.appendingPathComponent(name))
        return name
    }
    private func quarantineURL(_ name: String) throws -> URL {
        guard name.count == 73, UUID(uuidString: String(name.prefix(36))) != nil,
              name.dropFirst(36).first == "-", UUID(uuidString: String(name.suffix(36))) != nil else {
            throw ProjectStorageError.invalidPath
        }
        return trash.appendingPathComponent(name)
    }
    public func restoreQuarantine(_ name: String) throws {
        let source = try quarantineURL(name), id = UUID(uuidString: String(name.prefix(36)))!
        try fm.moveItem(at: source, to: directory(id))
    }
    public func purgeQuarantine(_ name: String) throws { try fm.removeItem(at: quarantineURL(name)) }
    /// Called only after metadata loads successfully, before accepting operations.
    /// Repairs an interrupted deletion before removing unreferenced source revisions.
    public func reconcile(_ records: [SavedProjectRecord]) throws {
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        // Corrupt references must never authorize destructive reconciliation.
        for record in records { _ = try sourceURL(record.sourceRelativePath, id: record.id) }
        let ids = Set(records.map(\.id)), paths = Set(records.map(\.sourceRelativePath))
        if fm.fileExists(atPath: trash.path) {
            for item in try fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                guard let id = UUID(uuidString: String(item.lastPathComponent.prefix(36))) else { continue }
                if ids.contains(id) {
                    if !fm.fileExists(atPath: directory(id).path) { try restoreQuarantine(item.lastPathComponent) }
                    else { throw ProjectStorageError.file("An interrupted deletion needs file recovery for \(id)") }
                } else { try purgeQuarantine(item.lastPathComponent) }
            }
        }
        for folder in try fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  (try folder.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { continue }
            if !ids.contains(id) { try fm.removeItem(at: folder); continue }
            let sources = folder.appendingPathComponent("Sources")
            guard fm.fileExists(atPath: sources.path) else { continue }
            guard (try sources.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw ProjectStorageError.invalidPath }
            for file in try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil) {
                if !paths.contains("\(id.uuidString)/Sources/\(file.lastPathComponent)") { try fm.removeItem(at: file) }
            }
        }
    }
}
