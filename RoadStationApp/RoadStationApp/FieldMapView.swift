import SwiftUI
import MapKit
import RoadStationCore
import RoadStationAppleCRS
import RoadStationFieldPosition

struct FieldSpatialView: View {
    let alignment: RoadStationCore.Alignment
    let unit: ProjectUnit
    @ObservedObject var session: FieldPositionSession
    var readoutHeight: CGFloat
    @Binding var engineeringView: Bool
    @State private var satellite = true
    @State private var mapError: String?

    var body: some View {
        Group {
            if let crs = session.confirmedCRS, !engineeringView, mapError == nil {
                FieldMapView(alignment: alignment, crs: crs, unit: unit, session: session,
                             readoutHeight: readoutHeight, satellite: $satellite,
                             engineeringView: $engineeringView, mapError: $mapError)
                    .id(crs.definition.crs.identifier + unit.rawValue)
            } else {
                FieldPlanarView(alignment: alignment, unit: unit, session: session, readoutHeight: readoutHeight,
                    showMap: session.confirmedCRS == nil ? nil : {
                        mapError = nil; engineeringView = false
                    })
                    .overlay(alignment: .topLeading) {
                        if let mapError {
                            Text("Map unavailable: \(mapError)").font(.caption).padding(8)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 12).padding(.top, readoutHeight + 24)
                                .accessibilityIdentifier("field-map-error")
                        }
                    }
            }
        }
        .onChange(of: session.confirmedCRS) { _, _ in mapError = nil }
    }
}

private struct FieldMapView: View {
    let alignment: RoadStationCore.Alignment
    let crs: ConfirmedProjectCRS
    let unit: ProjectUnit
    @ObservedObject var session: FieldPositionSession
    var readoutHeight: CGFloat
    @Binding var satellite: Bool
    @Binding var engineeringView: Bool
    @Binding var mapError: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drawing: FieldMapDrawing?
    @State private var markers: FieldMapMarkers?
    @State private var markerRequest = UUID()
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRect = MKMapRect.null
    @State private var isFollowing = true
    @State private var hasFollowed = false

    private var snapshot: FieldPositionSnapshot? {
        guard let snapshot = session.fieldPosition, snapshot.alignmentID == alignment.id,
              snapshot.crs == crs, snapshot.unit == unit else { return nil }
        return snapshot
    }
    private var matchingMarkers: FieldMapMarkers? { markers?.matches(snapshot) == true ? markers : nil }
    private var isCurrent: Bool {
        guard snapshot != nil, !session.displayedPositionIsStale else { return false }
        switch session.status {
        case .locationReady, .poorAccuracy, .ambiguousLocation, .calculating: return true
        default: return false
        }
    }
    private var transformer: PROJProjectCoordinateTransformer {
        get throws { try .init(resolution: .identified(crs.definition.crs), outputUnit: .linear(unit)) }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                map
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .onMapCameraChange(frequency: .continuous) { update in visibleRect = update.rect }
                    .onChange(of: camera) { _, position in if position.positionedByUser { isFollowing = false } }
                if drawing == nil {
                    ProgressView("Drawing alignment…").padding()
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else if snapshot != nil, matchingMarkers == nil {
                    ProgressView("Updating map position…").font(.caption).padding(8)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("field-map-loading")
                }
            }
            .overlay(alignment: .topTrailing) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Label("N", systemImage: "arrow.up").font(.caption.bold()).padding(12)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12)).padding(12)
                        .accessibilityLabel("North up")
                }
            }
            .overlay(alignment: .bottomTrailing) { controls(size: geometry.size) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Field geographic map")
            .accessibilityValue(spatialSummary)
            .accessibilityIdentifier("field-alignment-canvas")
            .task(id: scenePhase) {
                guard scenePhase == .active, drawing == nil else { return }
                do {
                    let transformer = try transformer
                    let alignment = alignment
                    let task = Task.detached(priority: .userInitiated) {
                        try FieldMapGeometry.drawing(alignment: alignment, transformer: transformer)
                    }
                    let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    try Task.checkCancellation()
                    drawing = value
                    if let markers = matchingMarkers, isCurrent, isFollowing { follow(markers, size: geometry.size) }
                    else { fitAlignment(size: geometry.size, pause: false) }
                } catch is CancellationError { }
                catch { if !Task.isCancelled { mapError = error.localizedDescription } }
            }
            .onChange(of: snapshot, initial: true) { _, _ in markerRequest = UUID() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { markers = nil }
                markerRequest = UUID()
            }
            .task(id: markerRequest) {
                guard scenePhase == .active, let snapshot else { markers = nil; return }
                do {
                    let transformer = try transformer
                    let task = Task.detached(priority: .userInitiated) {
                        try FieldMapGeometry.markers(snapshot: snapshot, transformer: transformer)
                    }
                    let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    guard !Task.isCancelled, value.matches(self.snapshot), scenePhase == .active else { return }
                    markers = value
                    if isCurrent, isFollowing { follow(value, size: geometry.size) }
                } catch is CancellationError { }
                catch { if !Task.isCancelled { mapError = error.localizedDescription } }
            }
            .onChange(of: readoutHeight) { _, _ in
                if let markers = matchingMarkers, isFollowing, isCurrent { follow(markers, size: geometry.size) }
            }
            .onChange(of: geometry.size) { _, size in
                if let markers = matchingMarkers, isFollowing, isCurrent { follow(markers, size: size) }
            }
        }
    }

    private var map: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if let drawing {
                ForEach(Array(drawing.polylines.enumerated()), id: \.offset) { _, points in
                    MapPolyline(coordinates: points.map(\.clLocation))
                        .stroke(Color(.systemBackground), lineWidth: 8)
                    MapPolyline(coordinates: points.map(\.clLocation))
                        .stroke(.blue, lineWidth: 4)
                }
            }
            if let markers = matchingMarkers {
                MapCircle(center: markers.phone.clLocation, radius: markers.snapshot.sample.horizontalAccuracyMeters)
                    .foregroundStyle(.blue.opacity(0.12))
                    .stroke(isCurrent ? .blue : Color(.label), style: .init(lineWidth: 1.5, dash: isCurrent ? [] : [5, 4]))
                MapPolyline(coordinates: [markers.phone.clLocation, markers.nearest.clLocation])
                    .stroke(Color(.label), style: .init(lineWidth: 2, dash: [5, 4]))
                Annotation(isCurrent ? "Phone" : "Last known position", coordinate: markers.phone.clLocation) {
                    Circle().fill(isCurrent ? Color.blue : Color(.systemBackground))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(isCurrent ? .blue : Color(.label), lineWidth: 2))
                        .padding(3).background(Color(.systemBackground), in: Circle())
                        .accessibilityLabel(isCurrent ? markers.snapshot.sample.source.rawValue : "Last known position")
                }
                Annotation(markers.snapshot.result.nearestLocationIsAmbiguous ? "Representative" : "Nearest",
                           coordinate: markers.nearest.clLocation) {
                    Image(systemName: markers.snapshot.result.nearestLocationIsAmbiguous ? "diamond" : "diamond.fill")
                        .foregroundStyle(Color(.label)).padding(3).background(Color(.systemBackground), in: Circle())
                }
                Annotation("Forward", coordinate: markers.nearest.clLocation, anchor: .bottom) {
                    Image(systemName: "arrow.up").font(.title2.bold())
                        .rotationEffect(.radians(forwardAngle(markers)))
                        .foregroundStyle(Color(.label)).padding(6)
                        .background(Color(.systemBackground), in: Circle()).padding(.bottom, 16)
                        .accessibilityLabel("Forward alignment direction determines left and right")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(satellite ? .imagery(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .accessibilityIdentifier("field-map")
    }

    private func controls(size: CGSize) -> some View {
        HStack(spacing: 8) {
            Button {
                isFollowing.toggle()
                if isFollowing, isCurrent, let markers = matchingMarkers { follow(markers, size: size) }
            } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: isFollowing ? "location.fill" : "location").frame(minWidth: 44, minHeight: 52)
                } else {
                    Label(isFollowing ? "Follow: On" : "Follow: Paused", systemImage: isFollowing ? "location.fill" : "location")
                        .font(.subheadline.bold()).frame(minHeight: 52)
                }
            }.accessibilityLabel(isFollowing ? "Follow: On" : "Follow: Paused").accessibilityIdentifier("field-follow")
            Button {
                if let markers = matchingMarkers { recenter(markers, size: size, preserveZoom: false) }
            } label: { Image(systemName: "scope").frame(minWidth: 44, minHeight: 52) }
                .accessibilityLabel("Recenter").accessibilityIdentifier("field-recenter").disabled(matchingMarkers == nil)
            Menu {
                Picker("Map style", selection: $satellite) {
                    Text("Satellite").tag(true).accessibilityIdentifier("field-map-satellite")
                    Text("Street Map").tag(false).accessibilityIdentifier("field-map-street")
                }
                Button("Engineering View") { engineeringView = true }.accessibilityIdentifier("field-engineering-view")
                Button("Fit Alignment") { fitAlignment(size: size) }
                Button("Zoom in") { zoom(1 / 1.5) }
                Button("Zoom out") { zoom(1.5) }
                Button("Pan north") { pan(x: 0, y: -0.25) }
                Button("Pan south") { pan(x: 0, y: 0.25) }
                Button("Pan east") { pan(x: 0.25, y: 0) }
                Button("Pan west") { pan(x: -0.25, y: 0) }
            } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 52) }
                .accessibilityLabel("Camera actions").accessibilityIdentifier("field-camera-actions")
                .accessibilityValue(satellite ? "Satellite" : "Street Map")
        }.buttonStyle(.plain).padding(.horizontal, 12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3).padding(12)
    }

    private func forwardAngle(_ markers: FieldMapMarkers) -> Double {
        guard let a = try? FieldMapGeometry.mapPoint(markers.nearest),
              let b = try? FieldMapGeometry.mapPoint(markers.forward) else { return 0 }
        return atan2(b.x - a.x, b.y - a.y)
    }
    private func fittedRect(_ points: [GeographicCoordinate], size: CGSize) -> MKMapRect {
        var rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: .init(width: 0, height: 0))) }
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let minimum = 50 * MKMapPointsPerMeterAtLatitude(points.first?.latitude ?? 0)
        let width = max(minimum, rect.width * 1.4), height = max(minimum, rect.height * 1.4)
        let top = readoutHeight + 24, bottom = 200.0
        let scale = min(max(1, size.width - 48) / width, max(40, size.height - top - bottom) / height)
        rect = MKMapRect(x: center.x - size.width / scale / 2,
                         y: center.y - size.height / scale / 2 - (top - bottom) / scale / 2,
                         width: size.width / scale, height: size.height / scale)
        return rect
    }
    private func fitAlignment(size: CGSize, pause: Bool = true) {
        guard let drawing else { return }
        if pause { isFollowing = false }
        setCamera(fittedRect(drawing.polylines.flatMap { $0 }, size: size))
    }
    private func follow(_ markers: FieldMapMarkers, size: CGSize) {
        recenter(markers, size: size, preserveZoom: hasFollowed)
        hasFollowed = true
    }
    private func recenter(_ markers: FieldMapMarkers, size: CGSize, preserveZoom: Bool) {
        var rect = fittedRect([markers.phone, markers.nearest], size: size)
        if preserveZoom, !visibleRect.isNull {
            let width = max(rect.width, visibleRect.width), height = max(rect.height, visibleRect.height)
            rect = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }
        setCamera(rect)
    }
    private func zoom(_ factor: Double) {
        guard !visibleRect.isNull else { return }
        isFollowing = false
        let width = visibleRect.width * factor, height = visibleRect.height * factor
        setCamera(.init(x: visibleRect.midX - width / 2, y: visibleRect.midY - height / 2, width: width, height: height))
    }
    private func pan(x: Double, y: Double) {
        guard !visibleRect.isNull else { return }
        isFollowing = false
        setCamera(.init(x: visibleRect.minX + visibleRect.width * x, y: visibleRect.minY + visibleRect.height * y,
                        width: visibleRect.width, height: visibleRect.height))
    }
    private func setCamera(_ rect: MKMapRect) {
        guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return }
        visibleRect = rect
        camera = .rect(rect)
    }
    private var spatialSummary: String {
        let drawingStatus = drawing == nil ? "Preparing alignment overlay." : "Alignment overlay ready."
        guard let snapshot else { return "\(alignment.name). \(drawingStatus) Waiting for a usable field position. North up." }
        let markerStatus = matchingMarkers == nil ? "Preparing position markers." :
            (snapshot.result.nearestLocationIsAmbiguous ? "Representative nearest point; ambiguous." : "Nearest point shown.")
        return "\(snapshot.alignmentName). \(drawingStatus) \(isCurrent ? snapshot.sample.source.rawValue : "Last known position"). Station \(snapshot.result.formattedStation), \(numeric(abs(snapshot.result.signedOffset), decimals: 1)) \(unit.symbol) \(sideLabel(snapshot.result.side)). Accuracy \(numeric(snapshot.accuracyInProjectUnits, decimals: 1)) \(unit.symbol). \(markerStatus) North up."
    }
}

private extension GeographicCoordinate {
    var clLocation: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
