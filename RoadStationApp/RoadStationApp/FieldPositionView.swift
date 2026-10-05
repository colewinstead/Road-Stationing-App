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
            Text(session.status == .stopped ? "Open Field Position to use phone location." : session.status.message)
                .font(.footnote).accessibilityIdentifier("field-status")
            Text("Confirm the CRS used to create the alignment. Location ranks choices only. Your confirmed CRS is saved with the project.")
                .font(.caption).foregroundStyle(.secondary)
        }.buttonStyle(.bordered)
        .sheet(isPresented: $showPicker) { CRSPickerView(session: session) }
        .task { catalog = try? await CRSCatalogStore.shared.catalog() }
    }
}

struct FieldPositionView: View {
    @ObservedObject var session: FieldPositionSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var panelExpanded = false
    @State private var showDetails = false
    @State private var showSetup = false
    @State private var catalog: CRSCatalog?
    @State private var readoutHeight: CGFloat = 240
    @State private var engineeringView = false
    #if DEBUG
    @State private var showInjection = false
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var accuracy = "10"
    @State private var injectionError: String?
    @FocusState private var editingInjection: Bool
    #endif
    private var position: FieldPositionSnapshot? { session.fieldPosition }
    private var displayedSample: LocationSample? { position?.sample ?? session.sample }
    private var displayedUnit: ProjectUnit? { position?.unit ?? session.project?.unit }
    private var freshnessDeadline: Date? {
        [position?.sample.timestamp, session.sample?.timestamp].compactMap { $0 }.min()
            .map { $0.addingTimeInterval(session.policy.maximumAgeSeconds + 0.01) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                GeometryReader { spatial in
                let readoutLimit = max(80, spatial.size.height - (dynamicTypeSize.isAccessibilitySize ? 300 : 200))
                let visibleReadoutHeight = min(readoutHeight, readoutLimit)
                ZStack(alignment: .topLeading) {
                    if let alignment = session.alignment, let unit = session.project?.unit {
                        FieldSpatialView(alignment: alignment, unit: unit, session: session, readoutHeight: visibleReadoutHeight,
                                         engineeringView: $engineeringView)
                            .id(alignment.id)
                    } else {
                        ContentUnavailableView("Select an alignment", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    ViewThatFits(in: .vertical) {
                        reading.padding(14)
                        ScrollView { reading.padding(14) }
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? max(1, geometry.size.width - 24) : min(330, max(1, geometry.size.width - 100)))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: FieldReadoutHeight.self, value: proxy.size.height)
                    })
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("field-result-card")
                    .frame(maxHeight: readoutLimit, alignment: .top).padding(12)
                    .onPreferenceChange(FieldReadoutHeight.self) { readoutHeight = $0 }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    let summary = safetySummary(now: Date())
                    let warning = Label(summary ?? "Current fix", systemImage: summary == nil || summary == "Current fix" ? "checkmark.circle" : "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    ViewThatFits(in: .vertical) {
                        warning
                        ScrollView { warning }
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore).accessibilityLabel(summary ?? "Current fix")
                    .accessibilityIdentifier("field-safety-status")
                    .frame(maxHeight: 100, alignment: .bottom)
                    .padding(.horizontal, 12).padding(.bottom, 86)
                }
                }
                bottomPanel
                    .frame(height: panelExpanded ? min(geometry.size.height * 0.55, max(100, geometry.size.height - 280)) : nil, alignment: .top)
                    .background(Color(.systemBackground))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: -3)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .navigationTitle("Field Position").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #if DEBUG
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            if editingInjection { Spacer(); Button("Done") { editingInjection = false } }
        } }
        #endif
        .onAppear {
            isVisible = true
            showSetup = session.confirmedCRS == nil
            panelExpanded = showSetup
            startLocationIfReady()
        }
        .onDisappear { isVisible = false; session.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startLocationIfReady() }
            else { session.stop() }
        }
        .onChange(of: session.confirmedCRS) { _, selection in
            if selection == nil { session.stop(); showSetup = true; panelExpanded = true }
            else { showSetup = false; panelExpanded = false; startLocationIfReady() }
        }
        .onChange(of: session.alignment?.id) { _, _ in startLocationIfReady() }
        .task(id: freshnessDeadline) {
            guard let deadline = freshnessDeadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled, isVisible, scenePhase == .active else { return }
            session.refresh(now: Date())
        }
        .task { catalog = try? await CRSCatalogStore.shared.catalog() }
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result = position?.result {
                Text("STA \(result.formattedStation)").font(.largeTitle.bold()).accessibilityIdentifier("live-station")
                Text("\(numeric(abs(result.signedOffset), decimals: 1)) \(displayedUnit?.symbol ?? "units") \(sideLabel(result.side))")
                    .font(.title2.bold()).accessibilityIdentifier("live-offset")
            } else {
                Text("STA —").font(.largeTitle.bold())
                Text("Offset —").font(.title2.bold())
            }
            Text(session.accuracyInProjectUnits().map {
                "GPS Accuracy: ±\(numeric($0, decimals: 1)) \(displayedUnit?.symbol ?? "units")"
            } ?? "GPS Accuracy: waiting for a valid fix")
                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("live-accuracy")
            HStack(alignment: .top, spacing: 6) {
                Text(displayedSample?.source.rawValue ?? "Device location")
                    .font(.footnote.weight(.semibold)).accessibilityIdentifier("location-source")
                    .accessibilityValue(session.isRunning ? "active" : "inactive")
                Spacer(minLength: 4)
                ProgressView().frame(width: 18, height: 18).opacity(session.isCalculating ? 1 : 0)
                    .accessibilityLabel("Updating field position").accessibilityIdentifier("field-calculation-activity")
                    .accessibilityHidden(!session.isCalculating)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true).monospacedDigit()
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Button { setPanelExpanded(!panelExpanded) } label: {
                VStack(spacing: 8) {
                    Capsule().fill(.secondary).frame(width: 36, height: 5).accessibilityHidden(true)
                    HStack(alignment: .top) {
                        Text(position?.alignmentName ?? session.alignment?.name ?? "Select an alignment")
                            .font(.headline).foregroundStyle(.primary).accessibilityIdentifier("live-alignment")
                        Spacer(minLength: 12)
                        Label(panelExpanded ? "Hide details" : "Details", systemImage: panelExpanded ? "chevron.down" : "chevron.up")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    }.frame(minHeight: 44)
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("field-details-toggle")
            .accessibilityValue(panelExpanded ? "Expanded" : "Collapsed")
            .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                if abs(value.translation.height) > 30 { setPanelExpanded(value.translation.height < 0) }
            })
            if panelExpanded {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(session.displayedPositionMessage).font(.body.weight(.semibold)).accessibilityIdentifier("live-status")
                        if position?.result.nearestLocationIsAmbiguous == true {
                            Label("AMBIGUOUS — representative station/offset", systemImage: "exclamationmark.triangle.fill")
                                .accessibilityIdentifier("live-ambiguity")
                        }
                        if position != nil {
                            switch session.status {
                            case .locationFailure, .transformationFailure, .stationingFailure,
                                 .invalidAccuracy, .invalidCoordinate, .invalidTimestamp:
                                Text(session.status.message)
                            default: EmptyView()
                            }
                        }
                        DisclosureGroup(isExpanded: $showDetails) {
                            if let point = position?.coordinate {
                                LabeledContent("Easting", value: numeric(point.x, decimals: 3))
                                LabeledContent("Northing", value: numeric(point.y, decimals: 3))
                            }
                            LabeledContent("CRS", value: position?.crs.definition.crs.identifier ?? session.confirmedCRS?.definition.crs.identifier ?? "CRS required")
                            LabeledContent("Units", value: displayedUnit.map(unitName) ?? "Unknown")
                            if let sample = displayedSample {
                                LabeledContent("Last fix", value: sample.timestamp.formatted(date: .omitted, time: .standard))
                            }
                            Text("Phone GPS is approximate. RoadStation does not provide survey-grade positioning.")
                            Text("When In Use only. Location runs automatically while this screen is open in the foreground.")
                        } label: { Text("Position details").frame(minHeight: 44) }
                        DisclosureGroup(isExpanded: $showSetup) {
                            ProjectCRSControls(session: session)
                        } label: { Text("Coordinate system & setup").frame(minHeight: 44) }
                        VStack(alignment: .leading, spacing: 8) {
                            AlignmentSegmentLegend()
                            Label("Phone position / last known fix", systemImage: "circle.circle")
                            Label("Nearest alignment point (representative if ambiguous)", systemImage: "diamond")
                            Label("Forward alignment direction determines LT / RT", systemImage: "arrow.right")
                            Text("The map is north up; Engineering View uses grid north. The ring shows approximate horizontal GPS uncertainty; it is not a guaranteed error boundary. The alignment drawing is display-only.")
                            Text("Satellite and street basemaps may be unavailable offline. Choose Engineering View in Camera actions to use the local alignment grid. Stationing does not depend on map imagery.")
                        }.font(.callout)
                        #if DEBUG
                        DisclosureGroup(isExpanded: $showInjection) {
                            Text("Enter WGS84 degrees and GPS accuracy in meters. This runs the same projection and geometry pipeline as device location.").font(.callout)
                            TextField("Latitude", text: $latitude).focused($editingInjection).accessibilityIdentifier("injected-latitude")
                            TextField("Longitude", text: $longitude).focused($editingInjection).accessibilityIdentifier("injected-longitude")
                            TextField("Accuracy (meters)", text: $accuracy).focused($editingInjection).accessibilityIdentifier("injected-accuracy")
                            Button("Inject geographic location") {
                                guard let lat = Double(latitude), let lon = Double(longitude), let meters = Double(accuracy) else {
                                    injectionError = "Enter numeric latitude, longitude and accuracy."; return
                                }
                                injectionError = nil; editingInjection = false
                                let now = Date()
                                Task {
                                    await session.inject(LocationSample(latitude: lat, longitude: lon,
                                        horizontalAccuracyMeters: meters, timestamp: now), now: now)
                                    showInjection = false; showSetup = false; showDetails = false
                                    setPanelExpanded(false)
                                }
                            }.accessibilityIdentifier("inject-location").disabled(session.confirmedCRS == nil)
                            if let injectionError { Text(injectionError).foregroundStyle(.red) }
                        } label: { Text("DEBUG location injection").frame(minHeight: 44) }
                        .textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
                        #endif
                    }.padding(16).buttonStyle(.bordered).controlSize(.large)
                }
            }
        }
    }
    private func setPanelExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { panelExpanded = expanded }
    }
    private func safetySummary(now: Date) -> String? {
        var messages: [String] = []
        if position == nil {
            switch session.status {
            case .crsUnavailable: messages.append("CRS unavailable — review setup")
            case .permissionDenied: messages.append("Location permission denied")
            case .permissionRestricted: messages.append("Location permission restricted")
            case .locationFailure, .transformationFailure, .stationingFailure: messages.append("Position unavailable — review details")
            default: messages.append(session.status.message)
            }
        } else if session.displayedPositionIsStale {
            messages.append("Stale — last known position")
        } else {
            switch session.status {
            case .locationReady, .poorAccuracy, .ambiguousLocation, .calculating: messages.append("Current fix")
            default: messages.append("Last known position — update unavailable")
            }
        }
        if position?.result.nearestLocationIsAmbiguous == true { messages.append("Ambiguous nearest point") }
        if let sample = displayedSample, sample.horizontalAccuracyMeters > session.policy.warningAccuracyMeters { messages.append("Poor GPS accuracy") }
        if !(position?.preciseAccuracy ?? session.preciseAccuracy), displayedSample?.source == .device { messages.append("Approximate location") }
        if let code = session.confirmedCRS?.definition.crs.epsgCode,
           CRSPickerModel.outsideAreaWarning(entry: catalog?.entry(code: code), sample: session.sample,
                permission: session.permission, policy: session.policy, now: now) != nil { messages.append("Outside CRS area of use") }
        if displayedSample?.source == .developerInjection { messages.append("DEBUG injected location") }
        return messages.isEmpty ? nil : messages.joined(separator: " · ")
    }
    private func startLocationIfReady() {
        guard isVisible, scenePhase == .active, session.confirmedCRS != nil,
              session.alignment != nil, !session.isRunning else { return }
        session.start()
    }
}
private struct FieldReadoutHeight: PreferenceKey {
    static let defaultValue: CGFloat = 240
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
func coordinateUnitName(_ unit: CoordinateUnit) -> String {
    switch unit { case .degree: "Degrees"; case .linear(let unit): unitName(unit) }
}
