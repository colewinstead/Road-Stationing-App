import SwiftUI
import RoadStationCore
import RoadStationHarnessSupport

struct EngineeringCanvas: View {
    @ObservedObject var model: WorkspaceModel
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @State private var fittedBounds: SegmentBounds?
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification = 1.0
    var body: some View {
        GeometryReader { geometry in
            let viewport = CanvasViewport(bounds: fittedBounds ?? model.bounds, width: geometry.size.width,
                height: geometry.size.height, zoom: zoom * magnification,
                pan: .init(x: pan.width + drag.width, y: pan.height + drag.height))
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    func screen(_ p: ProjectCoordinate) -> CGPoint {
                        let s = viewport.screen(p); return CGPoint(x: s.x, y: s.y)
                    }
                    var grid = Path()
                    for x in stride(from: 0.0, through: size.width, by: 40) {
                        grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height))
                    }
                    for y in stride(from: 0.0, through: size.height, by: 40) {
                        grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.secondary.opacity(0.13)), lineWidth: 0.5)
                    for polyline in model.polylines {
                        guard let first = polyline.points.first else { continue }
                        var path = Path(); path.move(to: screen(first))
                        for point in polyline.points.dropFirst() { path.addLine(to: screen(point)) }
                        let type = model.alignment.segments[polyline.segmentIndex].geometry
                        let color: Color
                        switch type { case .line: color = .primary; case .circularCurve: color = .blue; case .spiral: color = .purple }
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    if let query = model.queryPoint {
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
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    model.inspect(viewport.coordinate(.init(x: tap.location.x, y: tap.location.y)))
                })
                .highPriorityGesture(DragGesture(minimumDistance: 10)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in pan.width += value.translation.width; pan.height += value.translation.height })
                .simultaneousGesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = CanvasViewport.clampedZoom(zoom * value.magnification) })
                .accessibilityLabel("Engineering alignment canvas")
                .accessibilityHint("Tap to calculate station and offset in project coordinates")
                .accessibilityIdentifier("engineering-canvas")
                HStack(spacing: 10) {
                    Button { zoom = CanvasViewport.clampedZoom(zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Button { zoom = CanvasViewport.clampedZoom(zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                    Button("Fit") { fit() }.accessibilityIdentifier("fit-canvas")
                }.buttonStyle(.bordered).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8)
                if model.polylines.isEmpty, model.samplingError == nil {
                    ProgressView("Drawing alignment…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.25)))
        }
        .onChange(of: model.plotRevision) { _, _ in fit() }
    }
    private func fit() {
        let b = model.bounds
        var points = [ProjectCoordinate(x: b.minX, y: b.minY), .init(x: b.maxX, y: b.maxY)]
        if let query = model.queryPoint { points.append(query) }
        fittedBounds = SegmentBounds(points: points); zoom = 1; pan = .zero
    }
}
