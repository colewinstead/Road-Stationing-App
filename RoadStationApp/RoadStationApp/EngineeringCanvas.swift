import SwiftUI
import RoadStationCore
import RoadStationHarnessSupport
import RoadStationFieldPosition

struct EngineeringCanvas: View {
    @ObservedObject var model: WorkspaceModel
    var fieldPosition: FieldPositionSnapshot? = nil
    var fieldIsStale = false
    var fieldCamera: Binding<FieldCanvasCamera>? = nil
    var topInset: CGFloat = 0
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var fittedBounds: SegmentBounds?
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification = 1.0

    var body: some View {
        GeometryReader { geometry in
            let isField = fieldCamera != nil
            let inset = isField ? min(topInset, max(0, geometry.size.height - 240)) : 0
            let camera = fieldCamera?.wrappedValue
            let height = isField ? max(80, geometry.size.height - inset - 160) : geometry.size.height
            let viewport = CanvasViewport(bounds: camera?.bounds ?? fittedBounds ?? model.bounds,
                width: geometry.size.width, height: height,
                zoom: (camera?.zoom ?? zoom) * magnification,
                pan: .init(x: (camera?.pan.x ?? pan.width) + drag.width,
                           y: (camera?.pan.y ?? pan.height) + drag.height))
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    func screen(_ p: ProjectCoordinate) -> CGPoint {
                        let s = viewport.screen(p); return CGPoint(x: s.x, y: s.y + inset)
                    }
                    var grid = Path()
                    for x in stride(from: 0.0, through: size.width, by: 40) {
                        grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height))
                    }
                    for y in stride(from: 0.0, through: size.height, by: 40) {
                        grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.secondary.opacity(0.13)), lineWidth: 0.5)
                    if isField, let position = fieldPosition {
                        let p = screen(position.coordinate)
                        let radius = position.accuracyInProjectUnits * viewport.scale
                        let ring = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(ring, with: .color(.blue.opacity(0.1)))
                        context.stroke(ring, with: .color(fieldIsStale ? .primary : .blue),
                            style: .init(lineWidth: 1.5, dash: fieldIsStale ? [5, 4] : []))
                    }
                    for polyline in model.polylines {
                        guard let first = polyline.points.first else { continue }
                        var path = Path(); path.move(to: screen(first))
                        for point in polyline.points.dropFirst() { path.addLine(to: screen(point)) }
                        let type = model.alignment.segments[polyline.segmentIndex].geometry
                        context.stroke(path, with: .color(.white), lineWidth: isField ? 10 : 9)
                        context.stroke(path, with: .color(.black), lineWidth: isField ? 7 : 6)
                        context.stroke(path, with: .color(alignmentMapColor(type)),
                            style: StrokeStyle(lineWidth: isField ? 4 : 3, lineCap: .round, lineJoin: .round))
                    }
                    if isField, let position = fieldPosition {
                        let phone = screen(position.coordinate), nearest = screen(position.result.nearestPoint)
                        var connector = Path(); connector.move(to: phone); connector.addLine(to: nearest)
                        context.stroke(connector, with: .color(.primary), style: .init(lineWidth: 2, dash: [5, 4]))
                        let tangent = position.result.tangent
                        let tip = CGPoint(x: nearest.x + tangent.x * 36, y: nearest.y - tangent.y * 36)
                        var direction = Path(); direction.move(to: nearest); direction.addLine(to: tip)
                        direction.move(to: .init(x: tip.x - tangent.x * 10 - tangent.y * 6, y: tip.y + tangent.y * 10 - tangent.x * 6))
                        direction.addLine(to: tip)
                        direction.addLine(to: .init(x: tip.x - tangent.x * 10 + tangent.y * 6, y: tip.y + tangent.y * 10 + tangent.x * 6))
                        context.stroke(direction, with: .color(Color(.systemBackground)), lineWidth: 6)
                        context.stroke(direction, with: .color(.primary), style: .init(lineWidth: 2.5, lineCap: .round))
                        context.draw(Text("Forward").font(.caption.weight(.semibold)),
                                     at: .init(x: tip.x, y: tip.y - 14), anchor: .bottom)
                        let diamond = Path { path in
                            path.move(to: .init(x: nearest.x, y: nearest.y - 8))
                            path.addLine(to: .init(x: nearest.x + 8, y: nearest.y))
                            path.addLine(to: .init(x: nearest.x, y: nearest.y + 8))
                            path.addLine(to: .init(x: nearest.x - 8, y: nearest.y)); path.closeSubpath()
                        }
                        context.fill(diamond, with: .color(position.result.nearestLocationIsAmbiguous ? Color(.systemBackground) : .primary))
                        context.stroke(diamond, with: .color(.primary), lineWidth: 2)
                        context.draw(Text(position.result.nearestLocationIsAmbiguous ? "Representative" : "Nearest").font(.caption.weight(.semibold)),
                                     at: .init(x: nearest.x, y: nearest.y + 18), anchor: .top)
                        let outer = Path(ellipseIn: CGRect(x: phone.x - 10, y: phone.y - 10, width: 20, height: 20))
                        context.fill(outer, with: .color(Color(.systemBackground)))
                        let dot = Path(ellipseIn: CGRect(x: phone.x - 7, y: phone.y - 7, width: 14, height: 14))
                        if !fieldIsStale { context.fill(dot, with: .color(.blue)) }
                        context.stroke(dot, with: .color(fieldIsStale ? .primary : .blue), lineWidth: 2)
                        if phone.x < 16 || phone.x > size.width - 16 || phone.y < inset + 16 || phone.y > inset + height - 16 {
                            let cue = CGPoint(x: min(size.width - 50, max(50, phone.x)),
                                              y: min(inset + height - 20, max(inset + 20, phone.y)))
                            context.draw(Text(fieldIsStale ? "Last fix offscreen" : "Phone offscreen").font(.caption.bold()), at: cue)
                        }
                    } else if !isField, let query = model.queryPoint {
                        if let nearest = model.result?.nearestPoint ?? model.inverseNearestPoint {
                            var connector = Path(); connector.move(to: screen(query)); connector.addLine(to: screen(nearest))
                            context.stroke(connector, with: .color(.orange), style: .init(lineWidth: 1.5, dash: [5, 3]))
                            let p = screen(nearest)
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.blue))
                        }
                        let p = screen(query)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.orange))
                        context.stroke(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(.primary), lineWidth: 1)
                    }
                    if isField {
                        let length = 80 / viewport.scale
                        var scale = Path(); scale.move(to: .init(x: 16, y: size.height - 20)); scale.addLine(to: .init(x: 96, y: size.height - 20))
                        context.stroke(scale, with: .color(.primary), lineWidth: 2)
                        context.draw(Text("\(numeric(length, decimals: 1)) \(model.unit.symbol)").font(.caption),
                                     at: .init(x: 16, y: size.height - 26), anchor: .bottomLeading)
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    guard !isField else { return }
                    model.inspect(viewport.coordinate(.init(x: tap.location.x, y: tap.location.y)))
                })
                .highPriorityGesture(DragGesture(minimumDistance: 10)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onChanged { _ in fieldCamera?.wrappedValue.pause() }
                    .onEnded { value in
                        if let fieldCamera { fieldCamera.wrappedValue.move(x: value.translation.width, y: value.translation.height) }
                        else { pan.width += value.translation.width; pan.height += value.translation.height }
                    })
                .simultaneousGesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onChanged { _ in fieldCamera?.wrappedValue.pause() }
                    .onEnded { value in
                        if let fieldCamera { fieldCamera.wrappedValue.magnify(value.magnification) }
                        else { zoom = CanvasViewport.clampedZoom(zoom * value.magnification) }
                    })
                .accessibilityLabel(isField ? "Field alignment view" : "Engineering alignment canvas")
                .accessibilityValue(isField ? spatialSummary : "")
                .accessibilityHint(isField ? "Drag to pause Follow. Location updates continue. Camera controls provide zoom and pan actions." : "Tap to calculate station and offset in project coordinates")
                .accessibilityIdentifier(isField ? "field-alignment-canvas" : "engineering-canvas")
                if !isField {
                    HStack(spacing: 10) {
                        Button { zoom = CanvasViewport.clampedZoom(zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Zoom out")
                        Button { zoom = CanvasViewport.clampedZoom(zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Zoom in")
                        Button("Fit") { fit() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("fit-canvas")
                    }.buttonStyle(.bordered).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8)
                }
                if model.polylines.isEmpty, model.samplingError == nil {
                    ProgressView("Drawing alignment…").padding().background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error = model.samplingError {
                    Text("Drawing unavailable: \(error)").font(.callout).padding()
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: isField ? 0 : 14))
            .overlay(RoundedRectangle(cornerRadius: isField ? 0 : 14).stroke(.secondary.opacity(isField ? 0 : 0.25)))
        }
        .onChange(of: model.plotRevision) { _, _ in if fieldCamera == nil { fit() } }
    }
    private var spatialSummary: String {
        guard let position = fieldPosition else { return "\(model.alignment.name). Waiting for a usable field position. Grid north is up." }
        return "\(position.alignmentName). \(fieldIsStale ? "Last known position" : position.sample.source.rawValue). Station \(position.result.formattedStation), \(numeric(abs(position.result.signedOffset), decimals: 1)) \(position.unit.symbol) \(sideLabel(position.result.side)). Accuracy \(numeric(position.accuracyInProjectUnits, decimals: 1)) \(position.unit.symbol). \(position.result.nearestLocationIsAmbiguous ? "Representative nearest point; ambiguous." : "Nearest point shown.") Arrow follows forward alignment direction. Grid north is up."
    }
    private func fit() {
        let b = model.bounds
        var points = [ProjectCoordinate(x: b.minX, y: b.minY), .init(x: b.maxX, y: b.maxY)]
        if let query = model.queryPoint { points.append(query) }
        fittedBounds = SegmentBounds(points: points); zoom = 1; pan = .zero
    }
}

/// The original project-coordinate surface remains available without map tiles.
struct FieldPlanarView: View {
    @StateObject private var model: WorkspaceModel
    @ObservedObject var session: FieldPositionSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var readoutHeight: CGFloat
    var showMap: (() -> Void)?
    @State private var camera = FieldCanvasCamera()
    init(alignment: RoadStationCore.Alignment, unit: ProjectUnit, session: FieldPositionSession, readoutHeight: CGFloat,
         showMap: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: WorkspaceModel(alignment: alignment, unit: unit))
        self.session = session; self.readoutHeight = readoutHeight
        self.showMap = showMap
    }
    private var position: FieldPositionSnapshot? {
        guard session.fieldPosition?.alignmentID == model.alignment.id else { return nil }
        return session.fieldPosition
    }
    private var contextSpan: Double { 50 / (model.unit.metersPerUnit ?? 1) }
    private var positionIsCurrent: Bool {
        guard !session.displayedPositionIsStale else { return false }
        switch session.status {
        case .locationReady, .poorAccuracy, .ambiguousLocation, .calculating: return true
        default: return false
        }
    }
    var body: some View {
        EngineeringCanvas(model: model, fieldPosition: position, fieldIsStale: !positionIsCurrent,
                          fieldCamera: $camera, topInset: readoutHeight + 24)
            .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .bottomLeading : .topTrailing) {
                Label("N", systemImage: "arrow.up").font(.caption.bold()).padding(12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12)).padding(12)
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 70 : 0)
                    .accessibilityLabel("Grid north is up")
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    Button {
                        if camera.isFollowing { camera.pause() }
                        else { camera.resume(phone: positionIsCurrent ? position?.coordinate : nil,
                                             nearest: positionIsCurrent ? position?.result.nearestPoint : nil, contextSpan: contextSpan) }
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: camera.isFollowing ? "location.fill" : "location").frame(minWidth: 44, minHeight: 52)
                        } else {
                            Label(camera.isFollowing ? "Follow: On" : "Follow: Paused", systemImage: camera.isFollowing ? "location.fill" : "location")
                                .font(.subheadline.bold()).frame(minHeight: 52)
                        }
                    }.accessibilityLabel(camera.isFollowing ? "Follow: On" : "Follow: Paused")
                        .accessibilityIdentifier("field-follow")
                    Button {
                        if let position { camera.recenter(phone: position.coordinate, nearest: position.result.nearestPoint, contextSpan: contextSpan) }
                    } label: { Image(systemName: "scope").frame(minWidth: 44, minHeight: 52) }
                        .accessibilityLabel("Recenter").accessibilityIdentifier("field-recenter").disabled(position == nil)
                    Menu {
                        if let showMap { Button("Show Map", action: showMap).accessibilityIdentifier("field-show-map") }
                        Button("Fit Alignment") { camera.fitAlignment(model.bounds) }
                        Button("Zoom in") { camera.magnify(1.5) }
                        Button("Zoom out") { camera.magnify(1 / 1.5) }
                        Button("Pan north") { camera.move(x: 0, y: 80) }
                        Button("Pan south") { camera.move(x: 0, y: -80) }
                        Button("Pan east") { camera.move(x: -80, y: 0) }
                        Button("Pan west") { camera.move(x: 80, y: 0) }
                    } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 52) }
                        .accessibilityLabel("Camera actions").accessibilityIdentifier("field-camera-actions")
                }.buttonStyle(.plain).padding(.horizontal, 12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3).padding(12)
            }
            .task { await model.loadDrawing() }
            .onChange(of: position, initial: true) { _, value in
                if let value {
                    camera.follow(phone: value.coordinate, nearest: value.result.nearestPoint,
                                  contextSpan: contextSpan, isCurrent: positionIsCurrent)
                }
            }
    }
}
