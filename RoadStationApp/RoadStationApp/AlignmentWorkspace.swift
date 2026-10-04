import SwiftUI
import RoadStationCore
import RoadStationHarnessSupport
import RoadStationFieldPosition

struct AlignmentWorkspace: View {
    @StateObject private var model: WorkspaceModel
    @State private var tab = WorkspaceTab.inspect
    @ObservedObject private var field: FieldPositionSession
    init(alignment: RoadStationCore.Alignment, unit: ProjectUnit, field: FieldPositionSession) {
        _model = StateObject(wrappedValue: WorkspaceModel(alignment: alignment, unit: unit))
        self.field = field
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink("Live Location / Field Position") { FieldPositionView(session: field) }
                    .buttonStyle(.bordered).accessibilityIdentifier("open-field-position")
                EngineeringCanvas(model: model).frame(height: 300)
                HStack(spacing: 12) {
                    Label("Query", systemImage: "circle.fill").foregroundStyle(.orange)
                    Label(model.result == nil && model.inverseResult != nil ? "Centerline" : "Nearest", systemImage: "circle.fill").foregroundStyle(.blue)
                    Spacer()
                    Text("N ↑ · E →").foregroundStyle(.secondary)
                }.font(.caption)
                Text("Tap to inspect • drag to pan • pinch to zoom").font(.caption).foregroundStyle(.secondary)
                Picker("Workspace tool", selection: $tab) {
                    ForEach(WorkspaceTab.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("workspace-tabs")
                if model.busy { ProgressView("Calculating with RoadStationCore…") }
                if let error = model.error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("query-error") }
                if let error = model.samplingError { Text("Drawing unavailable: \(error)").foregroundStyle(.red) }
                switch tab {
                case .inspect: QueryCard(model: model)
                case .entry: EntryTools(model: model)
                case .info: AlignmentInfo(model: model)
                case .raw: RawInspection(model: model)
                }
                Text("Drawing samples are display-only. Manual queries use AlignmentEngine in unchanged project coordinates.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.alignment.name).navigationBarTitleDisplayMode(.inline)
        .task { await field.selectAlignment(model.alignment); await model.loadDrawing() }
    }
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case inspect = "Inspect", entry = "Entry", info = "Info", raw = "Raw"
    var id: String { rawValue }
}

struct EngineeringCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct QueryCard: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        EngineeringCard {
            if let inverse = model.inverseResult {
                Text("Calculated coordinate").font(.headline)
                LabeledContent("Easting", value: numeric(inverse.coordinate.x))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("inverse-easting").accessibilityValue(numeric(inverse.coordinate.x))
                LabeledContent("Northing", value: numeric(inverse.coordinate.y))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("inverse-northing").accessibilityValue(numeric(inverse.coordinate.y))
                LabeledContent("Geometric distance", value: numeric(inverse.geometricDistance))
                LabeledContent("Segment index (0-based)", value: String(inverse.nearestSegmentIndex))
                LabeledContent("Equation branch (0-based)", value: String(inverse.stationLocation.branchIndex))
                Divider()
                Text("Forward inspection of plotted point").font(.caption).foregroundStyle(.secondary)
            }
            if let result = model.result, let point = model.queryPoint {
                if result.nearestLocationIsAmbiguous {
                    Label("AMBIGUOUS nearest location", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.headline).accessibilityIdentifier("ambiguity-warning")
                    Text("The core returned a representative result. Do not treat it as a unique solution.").font(.footnote)
                }
                Text("STA \(result.formattedStation)").font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit().accessibilityIdentifier("result-station")
                Text("\(numeric(abs(result.signedOffset), decimals: 3)) \(model.unit.symbol) \(sideLabel(result.side))")
                    .font(.title2).monospacedDigit().accessibilityIdentifier("result-offset")
                Divider()
                LabeledContent("Query Easting", value: numeric(point.x))
                LabeledContent("Query Northing", value: numeric(point.y))
                LabeledContent("Nearest Easting", value: numeric(result.nearestPoint.x))
                LabeledContent("Nearest Northing", value: numeric(result.nearestPoint.y))
                LabeledContent("Segment", value: "\(result.nearestSegmentIndex) • \(result.segmentType)")
                LabeledContent("Bearing (CW from N)", value: "\(numeric(result.bearing * 180 / .pi, decimals: 5))°")
            } else if model.inverseResult == nil {
                Text("Inspect an alignment point").font(.headline)
                Text("Tap the canvas or use Entry to calculate a coordinate or station/offset.").foregroundStyle(.secondary)
            }
        }.font(.subheadline).monospacedDigit().textSelection(.enabled)
    }
}
