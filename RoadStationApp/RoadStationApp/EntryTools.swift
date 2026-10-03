import SwiftUI
import RoadStationCore
import RoadStationHarnessSupport

struct EntryTools: View {
    @ObservedObject var model: WorkspaceModel
    @State private var easting = ""
    @State private var northing = ""
    @State private var station = ""
    @State private var magnitude = "0"
    @State private var side = EntrySide.ON
    @FocusState private var focusedField: String?
    var body: some View {
        VStack(spacing: 16) {
            EngineeringCard {
                Text("Coordinate → station / offset").font(.headline)
                entry("Easting", text: $easting, id: "easting-entry")
                entry("Northing", text: $northing, id: "northing-entry")
                Button("Calculate station / offset") {
                    focusedField = nil; model.inspect(easting: easting, northing: northing)
                }.buttonStyle(.borderedProminent).disabled(model.busy).accessibilityIdentifier("calculate-forward")
            }
            EngineeringCard {
                Text("Station / offset → coordinate").font(.headline)
                entry("Station (427+38.42 or 42738.42)", text: $station, id: "station-entry")
                entry("Offset magnitude", text: $magnitude, id: "offset-entry")
                Picker("Side", selection: $side) {
                    ForEach(EntrySide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("side-picker")
                Button("Calculate Easting / Northing") {
                    focusedField = nil; model.inverse(station: station, magnitude: magnitude, side: side)
                }.buttonStyle(.borderedProminent).disabled(model.busy).accessibilityIdentifier("calculate-inverse")
                ForEach(model.branches, id: \.branchIndex) { location in
                    Button("Use branch \(location.branchIndex) • distance \(numeric(location.geometricDistance, decimals: 3))") {
                        focusedField = nil
                        model.inverse(station: station, magnitude: magnitude, side: side, branch: location.branchIndex)
                    }.buttonStyle(.bordered).accessibilityIdentifier("branch-\(location.branchIndex)")
                }
                Text("Positive = LT; negative = RT. Enter a nonnegative magnitude; ON requires zero. Branch and segment indices are zero-based.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            QueryCard(model: model)
        }
        .onChange(of: station) { _, _ in model.branches = [] }
        .onChange(of: magnitude) { _, _ in model.branches = [] }
        .onChange(of: side) { _, _ in model.branches = [] }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil } }
        }
    }
    private func entry(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focusedField, equals: id)
                .accessibilityIdentifier(id)
        }
    }
}
