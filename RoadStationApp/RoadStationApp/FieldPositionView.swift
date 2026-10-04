import SwiftUI
import RoadStationCore
import RoadStationFieldPosition
import RoadStationCRSCatalog

struct ProjectCRSControls: View {
    @ObservedObject var session: FieldPositionSession
    @State private var showPicker = false
    @State private var validating = false
    @State private var catalog: CRSCatalog?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let project = session.project, case .identified(let imported) = project.crsResolution {
                Text("LandXML: \(catalog?.entry(code: imported.epsgCode)?.name ?? imported.identifier)")
                Button("Confirm imported CRS") {
                    validating = true
                    Task { await session.confirmImportedCRS(); validating = false }
                }.accessibilityIdentifier("confirm-imported-crs").disabled(validating)
            } else if session.confirmedCRS == nil {
                Text("CRS required").font(.headline).accessibilityIdentifier("crs-required")
            }
            Button(session.confirmedCRS == nil ? "Choose Coordinate System" : "Other coordinate systems") { showPicker = true }
                .accessibilityIdentifier("open-crs-picker")
            if validating { ProgressView("Validating CRS…") }
            if let selection = session.confirmedCRS, let project = session.project {
                Text("\(catalog?.entry(code: selection.definition.crs.epsgCode)?.name ?? selection.definition.crs.identifier)")
                    .font(.headline)
                Text("\(selection.definition.crs.identifier) • \(unitName(project.unit))").accessibilityIdentifier("confirmed-crs")
                Text(selection.provenance.rawValue).font(.caption)
                Text("Native CRS units: \(coordinateUnitName(selection.definition.nativeUnit)). Output: \(unitName(project.unit)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let code = session.confirmedCRS?.definition.crs.epsgCode ?? session.project.flatMap { project -> Int? in
                    if case .identified(let crs) = project.crsResolution { return crs.epsgCode }; return nil
                }
                if let code, let warning = CRSPickerModel.outsideAreaWarning(entry: catalog?.entry(code: code), sample: session.sample,
                    permission: session.permission, policy: session.policy, now: context.date) {
                    Text(warning).foregroundStyle(.orange).accessibilityIdentifier("crs-area-warning")
                }
            }
            Text(session.status.message).font(.footnote).accessibilityIdentifier("field-status")
            Text("Confirm the CRS used to create the alignment. Location ranks choices only. Selection lasts for this session.")
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(.bordered)
        .sheet(isPresented: $showPicker) { CRSPickerView(session: session) }
        .task { catalog = try? await CRSCatalogStore.shared.catalog() }
    }
}

struct FieldPositionView: View {
    @ObservedObject var session: FieldPositionSession
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var statusHeight = 48
    #if DEBUG
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var accuracy = "10"
    @State private var injectionError: String?
    @FocusState private var editingInjection: Bool
    #endif
    var body: some View {
        let position = session.fieldPosition
        let displayedSample = position?.sample ?? session.sample
        let displayedUnit = position?.unit ?? session.project?.unit
        ScrollViewReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EngineeringCard {
                    HStack {
                        Text("Field Position").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 18, height: 18)
                            .opacity(session.isCalculating && position != nil ? 1 : 0)
                            .accessibilityLabel("Updating field position")
                            .accessibilityIdentifier("field-calculation-activity")
                            .accessibilityHidden(!session.isCalculating || position == nil)
                    }
                    Text(session.displayedPositionMessage)
                        .font(.body.weight(session.displayedPositionIsStale ? .semibold : .regular))
                        .foregroundStyle(session.displayedPositionIsStale || session.status != .locationReady ? Color.orange : Color.primary)
                        .lineLimit(2).frame(height: statusHeight, alignment: .topLeading)
                        .accessibilityIdentifier("live-status")
                    if let sample = displayedSample {
                        Text(sample.source.rawValue).font(.headline)
                            .foregroundStyle(sample.source == .device ? Color.secondary : Color.orange)
                            .accessibilityIdentifier("location-source")
                    }
                    if let result = position?.result {
                        if result.nearestLocationIsAmbiguous {
                            Text("AMBIGUOUS — representative station/offset")
                                .font(.headline).foregroundStyle(.red).accessibilityIdentifier("live-ambiguity")
                        }
                        Text("STA \(result.formattedStation)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .accessibilityIdentifier("live-station")
                        Text("\(numeric(abs(result.signedOffset), decimals: 1)) \(displayedUnit?.symbol ?? "units") \(sideLabel(result.side))")
                            .font(.title).accessibilityIdentifier("live-offset")
                    }
                    if let accuracy = session.accuracyInProjectUnits() {
                        Text("GPS Accuracy: ±\(numeric(accuracy, decimals: 1)) \(displayedUnit?.symbol ?? "units")")
                            .font(.title3.bold()).accessibilityIdentifier("live-accuracy")
                        if let sample = displayedSample, sample.horizontalAccuracyMeters > session.policy.warningAccuracyMeters {
                            Text("Poor accuracy — field position is approximate.").foregroundStyle(.orange)
                        }
                    } else { Text("GPS Accuracy: waiting for a valid fix").font(.headline) }
                    if !(position?.preciseAccuracy ?? session.preciseAccuracy), displayedSample?.source == .device {
                        Text("Precise Location is disabled. Approximate location warning.").foregroundStyle(.orange)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Location age: \(displayedSample.map { numeric(max(0, context.date.timeIntervalSince($0.timestamp)), decimals: 1) + " s" } ?? "—")")
                            .onChange(of: context.date) { _, now in session.refresh(now: now) }
                    }
                    if let point = position?.coordinate {
                        LabeledContent("Easting", value: numeric(point.x, decimals: 3))
                        LabeledContent("Northing", value: numeric(point.y, decimals: 3))
                    }
                    LabeledContent("Alignment", value: position?.alignmentName ?? session.alignment?.name ?? "Select an alignment")
                    LabeledContent("CRS", value: position?.crs.definition.crs.identifier ?? session.confirmedCRS?.definition.crs.identifier ?? "CRS required")
                    LabeledContent("Units", value: displayedUnit.map(unitName) ?? "Unknown")
                    Text("Phone GPS is approximate. RoadStation does not provide survey-grade positioning.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.monospacedDigit().id("live-result")
                    .accessibilityElement(children: .contain).accessibilityIdentifier("field-result-card")
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                EngineeringCard {
                    HStack {
                        Button("Start Location") { session.start() }.accessibilityIdentifier("start-location")
                            .disabled(session.confirmedCRS == nil || session.alignment == nil || session.isRunning)
                        Button("Stop Location") { session.stop() }.accessibilityIdentifier("stop-location")
                            .disabled(!session.isRunning)
                    }.buttonStyle(.bordered)
                    Text("When In Use only. Location stops when this screen closes or the app leaves the foreground.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                EngineeringCard { ProjectCRSControls(session: session) }
                #if DEBUG
                EngineeringCard {
                    Text("DEBUG location injection").font(.headline)
                    Text("Enter WGS84 degrees and GPS accuracy in meters. This runs the same projection and geometry pipeline as device location.").font(.caption)
                    TextField("Latitude", text: $latitude).focused($editingInjection).accessibilityIdentifier("injected-latitude")
                    TextField("Longitude", text: $longitude).focused($editingInjection).accessibilityIdentifier("injected-longitude")
                    TextField("Accuracy (meters)", text: $accuracy).focused($editingInjection).accessibilityIdentifier("injected-accuracy")
                    Button("Inject geographic location") {
                        guard let lat = Double(latitude), let lon = Double(longitude), let meters = Double(accuracy) else {
                            injectionError = "Enter numeric latitude, longitude and accuracy."; return
                        }
                        injectionError = nil
                        editingInjection = false
                        let now = Date()
                        Task { await session.inject(LocationSample(latitude: lat, longitude: lon,
                            horizontalAccuracyMeters: meters, timestamp: now), now: now)
                            viewport.scrollTo("live-result", anchor: .top)
                        }
                    }.accessibilityIdentifier("inject-location").disabled(session.confirmedCRS == nil)
                    if let injectionError { Text(injectionError).foregroundStyle(.red) }
                }.textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                #endif
            }.padding()
        }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Field Position").navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            if editingInjection { Spacer(); Button("Done") { editingInjection = false } }
        } }
        #endif
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { session.stop() } }
    }
}
func coordinateUnitName(_ unit: CoordinateUnit) -> String {
    switch unit { case .degree: "Degrees"; case .linear(let unit): unitName(unit) }
}
