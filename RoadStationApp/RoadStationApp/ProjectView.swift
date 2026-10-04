import SwiftUI
import UniformTypeIdentifiers
import RoadStationCore
import RoadStationProjects
import RoadStationCRSCatalog

struct ProjectView: View {
    @StateObject private var model = ProjectModel()
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var replacing: SavedProjectRecord?
    @State private var renameTarget: SavedProjectRecord?
    @State private var deleteTarget: SavedProjectRecord?
    @State private var catalog: CRSCatalog?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroll in
            List {
                statusSections
                Section("Projects") {
                    if model.projects.isEmpty, !model.isImporting {
                        ContentUnavailableView("No saved projects", systemImage: "folder",
                            description: Text("Import a LandXML once to keep its alignments and confirmed CRS on this device."))
                    }
                    ForEach(model.projects) { project in
                        Button { Task { await model.open(project.id) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(project.displayName).font(.headline)
                                Text("\(project.alignmentCount) alignments • \(unitName(project.unit))")
                                    .accessibilityIdentifier("saved-alignment-count-\(project.id)")
                                Text(crsSummary(project)).font(.subheadline)
                                if let opened = project.lastOpenedAt { Text("Last opened \(opened.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                                Text(project.sourceFileName).font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }.accessibilityIdentifier("saved-project-\(project.displayName)")
                            .contextMenu { projectActions(project) }
                            .swipeActions { Button("Delete", role: .destructive) { deleteTarget = project } }
                    }
                }
                Section {
                    Button { importing = true } label: { Label("Import Project", systemImage: "plus") }
                        .accessibilityIdentifier("import-project-home")
                }
                #if DEBUG
                Section("Synthetic developer samples") {
                    ForEach(SampleFile.all) { sample in
                        Button(sample.title) { model.loadSample(sample) }.accessibilityIdentifier("sample-\(sample.name)")
                    }
                    Text("DEBUG samples create saved projects on this device.").font(.caption).foregroundStyle(.secondary)
                }
                #endif
            }.onChange(of: model.error) { _, error in if error != nil { scroll.scrollTo("project-error", anchor: .top) } }
            }.navigationTitle("RoadStation")
                .toolbar { if path.isEmpty { ToolbarItem(placement: .topBarTrailing) {
                    Button("Import Project") { importing = true }.accessibilityIdentifier("import-landxml").disabled(model.isImporting)
                } } }
                .navigationDestination(for: UUID.self) { id in
                    SavedProjectDetail(model: model, id: id) { session in
                        projectDetail(session).id(session.saved.sourceRelativePath)
                    }
                }
        }
        .disabled(model.isImporting)
        .overlay(alignment: .top) {
            if model.isImporting { ProgressView("Opening project…").padding().background(.regularMaterial, in: Capsule()).padding(.top, 60) }
        }
        .task { await model.initialize(); catalog = try? await CRSCatalogStore.shared.catalog() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.flushChoices() } } }
        .onChange(of: model.openRevision) { _, _ in if let id = model.opened?.saved.id { path = [id] } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, UTType(importedAs: "com.roadstation.landxml", conformingTo: .xml)]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $replacing) { project in SourceReplacementView(project: project) { result in
            switch result {
            case .success(let url): Task { await model.replace(project.id, source: url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        } }
        .sheet(item: $renameTarget) { project in
            RenameProjectView(project: project) { name in Task { await model.rename(project.id, name: name) } }
        }
        .alert("Delete Project?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) { Task { if await model.delete(target.id) { path = [] } }; deleteTarget = nil }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { target in Text("Delete \(target.displayName) and all of its files from this device? This cannot be undone.") }
    }
    @ViewBuilder private var statusSections: some View {
        if let error = model.error {
            Section("Project error") {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("import-error").id("project-error")
                Button("Retry loading Projects") { Task { await model.reload() } }
                Button("Retry saving choices") { Task { await model.retrySave() } }
                Text("For a missing or damaged source, use Replace / Re-import LandXML in the project's menu.").font(.footnote)
            }
        }
        if let warning = model.maintenanceWarning {
            Section("Project notice") {
                Text(warning).foregroundStyle(.orange)
                Button("Retry file cleanup") { Task { await model.retryCleanup() } }
            }
        }
    }
    @ViewBuilder private func projectActions(_ project: SavedProjectRecord) -> some View {
        Button("Rename Project") { renameTarget = project }.accessibilityIdentifier("rename-project")
        Button("Replace / Re-import LandXML") { replacing = project }.accessibilityIdentifier("replace-project-source")
        Button("Delete Project", role: .destructive) { deleteTarget = project }.accessibilityIdentifier("delete-project")
    }
    private func projectDetail(_ session: OpenedProjectSession) -> some View {
        ScrollViewReader { scroll in
        List {
            statusSections
            Section("Project") {
                Text(model.isSavingChoices ? "Saving project choices…" : model.choicesSaveError == nil ? "Project saved" : "Choices not saved — retry saving")
                    .font(.caption).foregroundStyle(model.choicesSaveError == nil ? Color.secondary : Color.red)
                    .accessibilityIdentifier("project-save-status")
                LabeledContent("Name", value: session.saved.displayName)
                LabeledContent("Source LandXML", value: session.saved.sourceFileName)
                LabeledContent("Source saved", value: session.saved.sourceUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Units", value: unitName(session.project.unit))
                LabeledContent("Alignments", value: String(session.project.alignments.count)).accessibilityIdentifier("project-alignment-count")
                if let alignment = session.field.alignment {
                    LabeledContent("Last selected alignment", value: alignment.name).accessibilityIdentifier("restored-alignment")
                    NavigationLink("Continue \(alignment.name)") { AlignmentWorkspace(alignment: alignment, unit: session.project.unit, field: session.field) }
                        .accessibilityIdentifier("continue-alignment")
                    NavigationLink("Live Location / Field Position") { FieldPositionView(session: session.field) }.accessibilityIdentifier("project-field-position")
                }
            }
            Section("Project CRS") { ProjectCRSControls(session: session.field) }
            Section("Alignments") {
                ForEach(session.project.alignments) { alignment in
                    NavigationLink { AlignmentWorkspace(alignment: alignment, unit: session.project.unit, field: session.field) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(alignment.name).font(.headline)
                            Text("STA \(StationFormatter.string(alignment.startStation)) • \(numeric(alignment.totalGeometricLength, decimals: 3)) \(session.project.unit.symbol)")
                                .font(.subheadline).monospacedDigit()
                            Text("\(alignment.segments.count) segments").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("alignment-\(alignment.name)")
                }
            }
            if !session.warnings.isEmpty || !session.project.warnings.isEmpty {
                Section("Project warnings") {
                    ForEach(Array((session.warnings + session.project.warnings).enumerated()), id: \.offset) { _, warning in Text(warning).foregroundStyle(.orange) }
                }
            }
            Section("Project settings") { projectActions(session.saved) }
        }.onChange(of: model.error) { _, error in if error != nil { scroll.scrollTo("project-error", anchor: .top) } }
        }.navigationTitle(session.saved.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Import Project") { importing = true }.accessibilityIdentifier("import-landxml").disabled(model.isImporting)
            } }
    }
    private func crsSummary(_ project: SavedProjectRecord) -> String {
        guard let code = project.confirmedEPSG else { return "CRS not confirmed" }
        return (catalog?.entry(code: code)?.name ?? "Saved CRS") + " • EPSG:\(code)"
    }
}
/// Navigation destinations must observe the model independently of the home list.
private struct SavedProjectDetail<Content: View>: View {
    @ObservedObject var model: ProjectModel
    let id: UUID
    @ViewBuilder let content: (OpenedProjectSession) -> Content
    var body: some View {
        if let session = model.opened, session.saved.id == id {
            content(session)
        } else { ContentUnavailableView("Project unavailable", systemImage: "folder.badge.questionmark") }
    }
}
private struct RenameProjectView: View {
    @State private var name: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    init(project: SavedProjectRecord, save: @escaping (String) -> Void) {
        _name = State(initialValue: project.displayName); self.save = save
    }
    var body: some View {
        NavigationStack {
            Form { TextField("Project name", text: $name).accessibilityIdentifier("rename-project-name") }
                .navigationTitle("Rename Project").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(name); dismiss() }.accessibilityIdentifier("save-project-name")
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
private struct SourceReplacementView: View {
    let project: SavedProjectRecord
    let replace: (Result<URL, any Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    var body: some View {
        NavigationStack {
            Form {
                Text("Re-import LandXML for \(project.displayName). The current source is kept until the replacement parses and saves successfully. The project name, confirmed CRS and alignment identity are preserved.")
                Button("Choose replacement LandXML") { choosing = true }.accessibilityIdentifier("choose-replacement-source")
            }.navigationTitle("Replace LandXML").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.xml, UTType(importedAs: "com.roadstation.landxml", conformingTo: .xml)]) { result in
                    replace(result); dismiss()
                }
        }
    }
}
func crsReadinessText(_ readiness: CRSReadiness) -> String {
    switch readiness {
    case .unresolved: "Unresolved in LandXML"
    case .unavailable(let error): error.localizedDescription
    case .ready(let definition): "\(definition.crs.identifier) — horizontal conversion available"
    }
}
func unitName(_ unit: ProjectUnit) -> String {
    switch unit {
    case .usSurveyFoot: "US survey feet"
    case .internationalFoot: "International feet"
    case .meter: "Meters"
    case .unknown: "Unknown • unconverted source units"
    }
}
