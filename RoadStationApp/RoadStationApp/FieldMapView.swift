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
    @State private var cameraDistance: Double?
    @State private var chosenWidth: Double?
    @State private var isResizing = false
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
                    .onMapCameraChange(frequency: .continuous) { update in
                        visibleRect = update.rect; cameraDistance = update.camera.distance
                        if camera.positionedByUser, !isFollowing, !isResizing { chosenWidth = update.rect.width }
                    }
                    .onChange(of: camera) { _, position in
                        if position.positionedByUser { isFollowing = false; hasFollowed = true }
                    }
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
            .onChange(of: geometry.size) { _, _ in isResizing = true }
            .task(id: geometry.size) {
                isResizing = true
                // Let MapKit finish layout after the 0.2-second Details animation.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                isResizing = false
                if isFollowing, isCurrent, let markers = matchingMarkers {
                    follow(markers, size: geometry.size)
                } else if let width = chosenWidth, let cameraDistance, !visibleRect.isNull {
                    camera = .camera(MapCamera(centerCoordinate: MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate,
                        distance: cameraDistance * width / visibleRect.width, heading: 0, pitch: 0))
                }
            }
        }
    }

    private var map: some View {
        Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 1), interactionModes: [.pan, .zoom]) {
            if let drawing {
                AlignmentMapLines(drawing: drawing, alignment: alignment)
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
                if isFollowing { chosenWidth = visibleRect.isNull ? nil : visibleRect.width }
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
                if let markers = matchingMarkers { recenter(markers, size: size, preserveZoom: true) }
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
    private func fittedRect(_ points: [GeographicCoordinate], size: CGSize, viewport: MKMapSize? = nil) -> MKMapRect {
        var rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: .init(width: 0, height: 0))) }
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let minimum = 50 * MKMapPointsPerMeterAtLatitude(points.first?.latitude ?? 0)
        let width = max(minimum, rect.width * 1.4), height = max(minimum, rect.height * 1.4)
        let top = readoutHeight + 24, bottom = 200.0
        let scale = min(max(1, size.width - 48) / width, max(40, size.height - top - bottom) / height)
        let span = viewport ?? MKMapSize(width: size.width / scale, height: size.height / scale)
        rect = MKMapRect(x: center.x - span.width / 2,
                         y: center.y - span.height / 2 - (top - bottom) / max(1, size.height) * span.height / 2,
                         width: span.width, height: span.height)
        return rect
    }
    private func fitAlignment(size: CGSize, pause: Bool = true) {
        guard let drawing else { return }
        if pause { isFollowing = false }
        chosenWidth = nil; hasFollowed = false
        setCamera(fittedRect(drawing.polylines.flatMap { $0 }, size: size))
    }
    private func follow(_ markers: FieldMapMarkers, size: CGSize) {
        guard !isResizing else { return }
        recenter(markers, size: size, preserveZoom: hasFollowed)
        hasFollowed = true
    }
    private func recenter(_ markers: FieldMapMarkers, size: CGSize, preserveZoom: Bool) {
        if preserveZoom, !visibleRect.isNull, let cameraDistance {
            let width = chosenWidth ?? visibleRect.width
            chosenWidth = width
            let span = MKMapSize(width: width, height: visibleRect.height * width / visibleRect.width)
            let rect = fittedRect([markers.phone], size: size, viewport: span)
            camera = .camera(MapCamera(centerCoordinate: MKMapPoint(x: rect.midX, y: rect.midY).coordinate,
                                       distance: cameraDistance * width / visibleRect.width, heading: 0, pitch: 0))
        } else {
            setCamera(fittedRect([markers.phone, markers.nearest], size: size))
        }
    }
    private func zoom(_ factor: Double) {
        guard !visibleRect.isNull else { return }
        isFollowing = false; hasFollowed = true
        let width = visibleRect.width * factor, height = visibleRect.height * factor
        chosenWidth = width
        setCamera(.init(x: visibleRect.midX - width / 2, y: visibleRect.midY - height / 2, width: width, height: height))
    }
    private func pan(x: Double, y: Double) {
        guard !visibleRect.isNull else { return }
        isFollowing = false; hasFollowed = true
        chosenWidth = visibleRect.width
        setCamera(.init(x: visibleRect.minX + visibleRect.width * x, y: visibleRect.minY + visibleRect.height * y,
                        width: visibleRect.width, height: visibleRect.height))
    }
    private func setCamera(_ rect: MKMapRect) {
        guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return }
        visibleRect = rect
        camera = .rect(rect)
    }
    private var mapScaleSummary: String {
        guard !visibleRect.isNull else { return "" }
        let latitude = MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate.latitude
        return " Map width \(numeric(visibleRect.width * MKMetersPerMapPointAtLatitude(latitude), decimals: 2)) meters."
    }
    private var spatialSummary: String {
        let drawingStatus = drawing == nil ? "Preparing alignment overlay." : "Alignment overlay ready."
        guard let snapshot else { return "\(alignment.name). \(drawingStatus) Waiting for a usable field position. North up.\(mapScaleSummary)" }
        let markerStatus = matchingMarkers == nil ? "Preparing position markers." :
            (snapshot.result.nearestLocationIsAmbiguous ? "Representative nearest point; ambiguous." : "Nearest point shown.")
        return "\(snapshot.alignmentName). \(drawingStatus) \(isCurrent ? snapshot.sample.source.rawValue : "Last known position"). Station \(snapshot.result.formattedStation), \(numeric(abs(snapshot.result.signedOffset), decimals: 1)) \(unit.symbol) \(sideLabel(snapshot.result.side)). Accuracy \(numeric(snapshot.accuracyInProjectUnits, decimals: 1)) \(unit.symbol). \(markerStatus) North up.\(mapScaleSummary)"
    }
}

private extension GeographicCoordinate {
    var clLocation: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private let tangentMapColor = Color(red: 0, green: 0.9, blue: 1)
private let curveMapColor = Color(red: 1, green: 0.78, blue: 0)
private let spiralMapColor = Color(red: 1, green: 0.2, blue: 0.85)

func alignmentMapColor(_ geometry: SegmentGeometry) -> Color {
    switch geometry {
    case .line: tangentMapColor
    case .circularCurve: curveMapColor
    case .spiral: spiralMapColor
    }
}

struct AlignmentSegmentLegend: View {
    private var labels: some View {
        Group {
            item("Tangent", color: tangentMapColor)
            item("Curve", color: curveMapColor)
            item("Spiral", color: spiralMapColor)
        }
    }
    private func item(_ title: String, color: Color) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Capsule().fill(color).frame(width: 22, height: 4)
                .padding(1.5).background(.black, in: Capsule())
                .padding(1.5).background(.white, in: Capsule())
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { labels }
            VStack(alignment: .leading, spacing: 8) { labels }
        }.font(.caption.bold())
    }
}

private struct AlignmentMapLines: MapContent {
    let drawing: FieldMapDrawing
    let alignment: RoadStationCore.Alignment
    var body: some MapContent {
        ForEach(Array(drawing.polylines.enumerated()), id: \.offset) { index, points in
            MapPolyline(coordinates: points.map(\.clLocation)).stroke(.white, lineWidth: 10)
            MapPolyline(coordinates: points.map(\.clLocation)).stroke(.black, lineWidth: 7)
            MapPolyline(coordinates: points.map(\.clLocation))
                .stroke(alignmentMapColor(alignment.segments[index].geometry), lineWidth: 4)
        }
    }
}

struct InspectionSpatialView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var field: FieldPositionSession
    @State private var satellite = true
    @State private var engineeringView = false
    @State private var mapError: String?

    var body: some View {
        Group {
            if let crs = field.confirmedCRS, !engineeringView, mapError == nil {
                InspectionMapView(model: model, crs: crs, satellite: $satellite,
                                  engineeringView: $engineeringView, mapError: $mapError)
                    .id(crs.definition.crs.identifier + model.unit.rawValue)
            } else {
                EngineeringCanvas(model: model)
                    .overlay(alignment: .topLeading) {
                        if field.confirmedCRS != nil {
                            Button("Show Map") { mapError = nil; engineeringView = false }
                                .buttonStyle(.borderedProminent).padding(8)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let mapError {
                            Text("Map unavailable: \(mapError)").font(.caption).padding(8)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14))
            .onChange(of: field.confirmedCRS) { _, _ in mapError = nil }
    }
}

private struct InspectionMapView: View {
    @ObservedObject var model: WorkspaceModel
    let crs: ConfirmedProjectCRS
    @Binding var satellite: Bool
    @Binding var engineeringView: Bool
    @Binding var mapError: String?
    @State private var drawing: FieldMapDrawing?
    @State private var markerPoints: [ProjectCoordinate] = []
    @State private var markers: [GeographicCoordinate] = []
    @State private var fittedRevision = -1
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRect = MKMapRect.null

    private var transformer: PROJProjectCoordinateTransformer {
        get throws { try .init(resolution: .identified(crs.definition.crs), outputUnit: .linear(model.unit)) }
    }
    private var queryPoints: [ProjectCoordinate] {
        guard let query = model.queryPoint else { return [] }
        return [query, model.result?.nearestPoint ?? model.inverseNearestPoint].compactMap { $0 }
    }
    private var matchingMarkers: [GeographicCoordinate] { markerPoints == queryPoints ? markers : [] }

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $camera, bounds: MapCameraBounds(minimumDistance: 1), interactionModes: [.pan, .zoom]) {
                    if let drawing { AlignmentMapLines(drawing: drawing, alignment: model.alignment) }
                    if let query = matchingMarkers.first {
                        Annotation("Query", coordinate: query.clLocation) {
                            Circle().fill(.orange).frame(width: 12, height: 12).padding(3).background(.white, in: Circle())
                        }
                    }
                    if matchingMarkers.count == 2 {
                        let query = matchingMarkers[0], nearest = matchingMarkers[1]
                        MapPolyline(coordinates: [query.clLocation, nearest.clLocation])
                            .stroke(.white, lineWidth: 4)
                        MapPolyline(coordinates: [query.clLocation, nearest.clLocation])
                            .stroke(.black, style: .init(lineWidth: 2, dash: [5, 4]))
                        Annotation(model.result?.nearestLocationIsAmbiguous == true ? "Representative" : "Nearest", coordinate: nearest.clLocation) {
                            Image(systemName: model.result?.nearestLocationIsAmbiguous == true ? "diamond" : "diamond.fill")
                                .foregroundStyle(.blue).padding(3).background(.white, in: Circle())
                        }
                    }
                }
                .mapStyle(satellite ? .imagery(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapScaleView() }
                .onMapCameraChange(frequency: .continuous) { visibleRect = $0.rect }
                .onTapGesture { location in
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    do {
                        let geographic = try GeographicCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        model.inspect(try transformer.projectCoordinate(from: geographic))
                    } catch { model.error = error.localizedDescription }
                }
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Picker("Map style", selection: $satellite) {
                            Text("Satellite").tag(true)
                            Text("Street Map").tag(false)
                        }
                        Button("Engineering View") { engineeringView = true }
                        Button("Fit Alignment") { fit() }
                        Button("Zoom in") { zoom(1 / 1.5) }
                        Button("Zoom out") { zoom(1.5) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }.accessibilityLabel("Inspection map actions").accessibilityIdentifier("inspection-map-actions")
                        .accessibilityValue(satellite ? "Satellite" : "Street Map").padding(8)
                }
                .overlay {
                    if drawing == nil { ProgressView("Drawing alignment…").padding().background(.regularMaterial) }
                }
                .task {
                    do {
                        let alignment = model.alignment, transformer = try transformer
                        let task = Task.detached(priority: .userInitiated) {
                            try FieldMapGeometry.drawing(alignment: alignment, transformer: transformer)
                        }
                        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                        try Task.checkCancellation()
                        drawing = value; fit()
                    } catch is CancellationError { }
                    catch { if !Task.isCancelled { mapError = error.localizedDescription } }
                }
                .task(id: queryPoints) {
                    let points = queryPoints
                    do {
                        let transformer = try transformer
                        let task = Task.detached(priority: .userInitiated) {
                            try transformer.geographicCoordinates(from: points.map { ProjectCoordinate(x: $0.x, y: $0.y) })
                        }
                        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                        guard !Task.isCancelled, points == queryPoints else { return }
                        markerPoints = points; markers = value
                        if fittedRevision != model.plotRevision { fit() }
                    } catch is CancellationError { }
                    catch { if !Task.isCancelled { mapError = error.localizedDescription } }
                }
                .onChange(of: model.plotRevision) { _, _ in
                    if markerPoints == queryPoints { fit() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspection-map")
        .accessibilityValue(drawing == nil ? "Preparing alignment overlay" : "Alignment overlay ready; north up")
    }
    private func fit() {
        guard let drawing else { return }
        let points = drawing.polylines.flatMap { $0 } + matchingMarkers
        let rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.clLocation), size: .init(width: 0, height: 0))) }
        let margin = max(10 * MKMapPointsPerMeterAtLatitude(points.first?.latitude ?? 0), max(rect.width, rect.height) * 0.15)
        camera = .rect(rect.insetBy(dx: -margin, dy: -margin))
        fittedRevision = model.plotRevision
    }
    private func zoom(_ factor: Double) {
        guard !visibleRect.isNull else { return }
        let width = visibleRect.width * factor, height = visibleRect.height * factor
        camera = .rect(.init(x: visibleRect.midX - width / 2, y: visibleRect.midY - height / 2, width: width, height: height))
    }
}
