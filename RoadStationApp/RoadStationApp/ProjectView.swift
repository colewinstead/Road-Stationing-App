import SwiftUI
import UniformTypeIdentifiers
import RoadStationCore

struct ProjectView: View {
    @StateObject private var model = ProjectModel()
    @State private var showImporter = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Phase 1.5 developer harness", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Horizontal engineering coordinates. Independent ORD numerical validation is pending.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { showImporter = true } label: { Label("Import LandXML", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("import-landxml").disabled(model.isImporting)
                    if model.isImporting { ProgressView("Reading LandXML…") }
                }
                if let error = model.error {
                    Section("Import error") { Text(error).foregroundStyle(.red).accessibilityIdentifier("import-error") }
                }
                if let project = model.project {
                    Section("Project") {
                        LabeledContent("Name", value: project.name)
                        LabeledContent("Units", value: unitName(project.unit))
                        LabeledContent("Coordinate system", value: project.coordinateSystemDescription ?? "Not specified")
                        LabeledContent("Alignments", value: String(project.alignments.count))
                        Text(model.source).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Alignments") {
                        ForEach(project.alignments) { alignment in
                            NavigationLink {
                                AlignmentWorkspace(alignment: alignment, unit: project.unit)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(alignment.name).font(.headline)
                                    Text("STA \(StationFormatter.string(alignment.startStation))  •  \(numeric(alignment.totalGeometricLength, decimals: 3)) \(project.unit.symbol)")
                                        .font(.subheadline).monospacedDigit()
                                    Text("\(alignment.segments.count) segments").font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("alignment-\(alignment.name)")
                        }
                    }
                    if !project.warnings.isEmpty {
                        Section("Project warnings") {
                            ForEach(Array(project.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote) }
                        }
                    }
                } else if !model.isImporting {
                    Section { ContentUnavailableView("No project loaded", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Import .xml or .landxml from Files, or load a synthetic developer sample.")) }
                }
                #if DEBUG
                Section("Synthetic developer samples") {
                    ForEach(SampleFile.all) { sample in
                        Button(sample.title) { model.loadSample(sample) }
                            .disabled(model.isImporting).accessibilityIdentifier("sample-\(sample.name)")
                    }
                    Text("Samples test the harness. They are not real ORD numerical validation.").font(.caption).foregroundStyle(.secondary)
                }
                #endif
                Section { Text("GPS: Not available in Phase 1.5\nImported project data exists only for this session.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("RoadStation")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, UTType(importedAs: "com.roadstation.landxml", conformingTo: .xml)]) { result in
                switch result {
                case .success(let url): model.importFile(url)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
        }
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
