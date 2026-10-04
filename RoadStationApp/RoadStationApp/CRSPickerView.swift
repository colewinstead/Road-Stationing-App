import SwiftUI
import RoadStationCore
import RoadStationFieldPosition
import RoadStationCRSCatalog

struct CRSPickerView: View {
    @ObservedObject var session: FieldPositionSession
    @StateObject private var model = CRSPickerModel(locationService: CoreLocationRecommendationService())
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Recommended"
    @State private var query = ""
    @State private var candidate: CRSCatalogEntry?
    @State private var candidateReason: String?
    @State private var showManual = false
    @FocusState private var editingSearch: Bool
    @ScaledMetric private var recommendationStatusHeight = 110.0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Catalog section", selection: $tab) {
                    Text("Recommended").tag("Recommended")
                    Text("Browse").tag("Browse")
                    Text("Search").tag("Search")
                }.pickerStyle(.segmented).padding().accessibilityIdentifier("crs-picker-tabs")
                if model.catalog == nil, model.error == nil { ProgressView("Loading coordinate systems…") }
                if let error = model.error { Text(error).foregroundStyle(.orange).padding() }
                if tab == "Search" {
                    TextField("Name, state, datum, units or EPSG", text: $query)
                        .textFieldStyle(.roundedBorder).padding(.horizontal).focused($editingSearch)
                        .submitLabel(.search).onSubmit { editingSearch = false }
                        .accessibilityIdentifier("crs-search")
                        .task(id: query + (model.catalog?.epsgVersion ?? "")) { await model.search(query) }
                    List {
                        Section {
                            if model.searchResults.isEmpty { Text(query.isEmpty ? "Enter a name or EPSG code." : "No matching coordinate systems.") }
                            ForEach(model.searchResults) { entry in row(entry) }
                        } header: { Text("\(model.searchResults.count) results").accessibilityIdentifier("crs-search-count") }
                        manualSection
                    }.scrollDismissesKeyboard(.interactively)
                } else if tab == "Browse" {
                    List {
                        Section("US State Plane") {
                            let groups = Dictionary(grouping: model.catalog?.statePlaneEntries ?? [], by: { $0.statePlane!.state })
                            ForEach(groups.keys.sorted(), id: \.self) { state in
                                NavigationLink(state) {
                                    List {
                                        let zones = Dictionary(grouping: groups[state] ?? [], by: { $0.statePlane!.zone })
                                        ForEach(zones.keys.sorted(), id: \.self) { zone in
                                            Section(zone) { ForEach((zones[zone] ?? []).sorted { $0.name < $1.name }) { entry in row(entry) } }
                                        }
                                    }.navigationTitle(state)
                                }
                            }
                        }
                        manualSection
                    }
                } else {
                    List {
                        if let project = session.project, case .identified(let imported) = project.crsResolution {
                            Section("Imported from LandXML") {
                                Text(model.catalog?.entry(code: imported.epsgCode)?.name ?? imported.identifier)
                                Text(imported.identifier).monospacedDigit()
                                Button("Confirm imported CRS") { Task { await session.confirmImportedCRS(); if session.confirmedCRS != nil { dismiss() } } }
                                    .accessibilityIdentifier("picker-confirm-imported")
                                if let warning = model.capturedAreaWarning(entry: model.catalog?.entry(code: imported.epsgCode)) {
                                    Text(warning).foregroundStyle(.orange)
                                }
                            }
                        }
                        Section("Recommended near current location") {
                            recommendationStatus
                            if let location = model.recommendationLocation {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Location accuracy ±\(recommendationAccuracy(location))").monospacedDigit()
                                        .accessibilityIdentifier("crs-location-accuracy")
                                    Text("\(location.sample.source.rawValue) • Captured \(location.sample.timestamp.formatted(date: .omitted, time: .standard))")
                                        .font(.caption).monospacedDigit()
                                    if location.isApproximate {
                                        Text("Approximate recommendations — location accuracy is poor or Precise Location is off.").foregroundStyle(.orange)
                                    }
                                }
                                let recommendations = model.capturedRecommendations(unit: session.project?.unit ?? .unknown)
                                if recommendations.isEmpty { Text("No State Plane areas found nearby. Browse or search for the alignment's CRS.") }
                                ForEach(recommendations) { item in row(item.entry, reason: item.reason) }
                            }
                            Text("Location ranks choices only. Confirm the CRS used to create the alignment; newer datums are not interchangeable with older designs.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Browse State Plane") { tab = "Browse" }
                            Button("Search all supported CRS") { tab = "Search" }
                        }
                        manualSection
                        #if DEBUG
                        Section("DEBUG recommendation position") {
                            Text("Synthetic WGS84 32.3°, −90.2°, ±30 m. Retained for this picker only. Never starts Field Position.").font(.caption)
                        }
                        #endif
                    }

                }
            }
            .navigationTitle("Choose CRS").navigationBarTitleDisplayMode(.inline)
             .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    if editingSearch { Spacer(); Button("Done") { editingSearch = false } }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DEBUG fix") {
                        model.injectRecommendation(LocationSample(latitude: 32.3, longitude: -90.2, horizontalAccuracyMeters: 30,
                            timestamp: Date(), source: .developerInjection))
                    }.accessibilityIdentifier("inject-crs-recommendation")
                }
                #endif
            }
            .task { model.openRecommendationLocation(); await model.load() }
            .onDisappear { model.closeRecommendationLocation() }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .onChange(of: tab) { _, _ in editingSearch = false }
            .sheet(item: $candidate, onDismiss: { model.cancelPreview() }) { entry in
                CRSConfirmationView(entry: entry, session: session, recommendationLocation: model.recommendationLocation, recommendationReason: candidateReason) {
                    model.preview(entry)
                    await model.confirm(in: session)
                    if session.confirmedCRS?.definition.crs.epsgCode == entry.code { candidate = nil; dismiss() }
                }
            }
            .sheet(isPresented: $showManual) { ManualEPSGView(session: session) { dismiss() } }
        }
    }
    private var manualSection: some View {
        Section { Button("Enter EPSG manually (advanced)") { showManual = true }.accessibilityIdentifier("open-manual-epsg") }
    }
    private func row(_ entry: CRSCatalogEntry, reason: String? = nil) -> some View {
        Button { model.preview(entry); candidateReason = reason; candidate = entry } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.headline)
                Text("\(entry.identifier) • \(entry.nativeUnit.label)").font(.subheadline).monospacedDigit()
                if let sp = entry.statePlane { Text("State Plane — \(sp.zone)").font(.caption) }
                Text(entry.compatibility(with: session.project?.unit ?? .unknown).label).font(.caption)
                if let reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                if entry.deprecated { Text("Deprecated EPSG definition — verify design records").font(.caption).foregroundStyle(.orange) }
            }.foregroundStyle(.primary)
        }.accessibilityIdentifier("crs-row-\(entry.code)")
    }
    private var recommendationStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView().frame(width: 18, height: 18)
                .opacity(model.recommendationStatus.isAcquiring ? 1 : 0).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.recommendationStatus.message).font(.callout)
                    .accessibilityIdentifier("crs-recommendation-status")
                switch model.recommendationStatus {
                case .needsPermission:
                    Button("Use My Location") { model.useMyLocation() }.accessibilityIdentifier("crs-use-location")
                case .failed:
                    Button("Try Location Again") { model.useMyLocation() }.accessibilityIdentifier("crs-use-location")
                case .ready:
                    Button("Refresh Location") { model.useMyLocation() }.accessibilityIdentifier("crs-use-location")
                default: EmptyView()
                }
            }
        }.frame(maxWidth: .infinity, minHeight: recommendationStatusHeight, maxHeight: recommendationStatusHeight, alignment: .topLeading)
    }
    private func recommendationAccuracy(_ location: RecommendationLocationSnapshot) -> String {
        let unit = session.project?.unit ?? .unknown
        if let metersPerUnit = unit.metersPerUnit {
            return "\(numeric(location.sample.horizontalAccuracyMeters / metersPerUnit, decimals: 1)) \(unitName(unit))"
        }
        return "\(numeric(location.sample.horizontalAccuracyMeters, decimals: 1)) m"
    }

}

private struct CRSConfirmationView: View {
    let entry: CRSCatalogEntry
    @ObservedObject var session: FieldPositionSession
    let recommendationLocation: RecommendationLocationSnapshot?
    let recommendationReason: String?
    let confirm: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var validating = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Use this coordinate system?") {
                    Text(entry.name).font(.headline)
                    Text(entry.identifier).monospacedDigit().accessibilityIdentifier("crs-confirmation-code")
                    LabeledContent("Project units", value: session.project.map { unitName($0.unit) } ?? "Unknown")
                    LabeledContent("CRS native units", value: entry.nativeUnit.label)
                    Text(entry.compatibility(with: session.project?.unit ?? .unknown).label)
                    Text(entry.datum)
                    if let recommendationReason { Text("Recommendation when selected: \(recommendationReason)").font(.footnote) }
                    if entry.compatibility(with: session.project?.unit ?? .unknown) == .convertible {
                        Text("PROJ output will be explicitly converted to the project's declared units. This does not change the alignment's coordinates.")
                    }
                    if let location = recommendationLocation {
                        if entry.contains(location.point) {
                            Text("The captured one-time location falls within the published area of use. Location cannot identify the alignment's CRS.")
                        } else if !entry.areas.isEmpty {
                            Text("The one-time recommendation location appears outside this CRS's published area of use.").foregroundStyle(.orange)
                        }
                    }
                    DisclosureGroup("Published area of use") {
                        ForEach(Array(entry.areas.enumerated()), id: \.offset) { _, area in Text(area.name).font(.caption) }
                        Text("Published bounds are approximate rectangles, not zone polygons.").font(.caption)
                    }
                    Text("Confirm against the design records. Selecting a different CRS clears the current field-position result.").font(.footnote)
                }
                Section {
                    Button("Use CRS") { validating = true; Task { await confirm(); validating = false } }
                        .disabled(validating || entry.compatibility(with: session.project?.unit ?? .unknown) == .incompatible)
                        .accessibilityIdentifier("use-catalog-crs")
                    if validating { ProgressView("Validating CRS…") }
                    if case .crsUnavailable = session.status { Text(session.status.message).foregroundStyle(.red) }
                }
            }.navigationTitle("Confirm CRS").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(validating) } }
        }.interactiveDismissDisabled(validating)
    }
}

struct ManualEPSGView: View {
    @ObservedObject var session: FieldPositionSession
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var epsg = ""
    @State private var validating = false
    @FocusState private var editing: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Advanced EPSG entry") {
                    Text("Enter the coordinate system used by the alignment. Confirming this code validates PROJ support and project-unit conversion.")
                    TextField("EPSG code", text: $epsg).keyboardType(.numbersAndPunctuation).focused($editing).accessibilityIdentifier("epsg-entry")
                    Button("Validate and use EPSG") {
                        editing = false; validating = true
                        Task { await session.selectEPSG(epsg); validating = false; if session.confirmedCRS != nil { completed() } }
                    }.accessibilityIdentifier("select-epsg").disabled(validating)
                    if validating { ProgressView("Validating CRS…") }
                    Text(session.status.message).accessibilityIdentifier("manual-epsg-status")
                }
            }.navigationTitle("Manual EPSG").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
                }
        }.interactiveDismissDisabled(validating)
    }
}
