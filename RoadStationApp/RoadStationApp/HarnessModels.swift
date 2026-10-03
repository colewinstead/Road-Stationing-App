import Foundation
import SwiftUI
import RoadStationCore
import RoadStationHarnessSupport

@MainActor
final class ProjectModel: ObservableObject {
    @Published var project: Project?
    @Published var source = ""
    @Published var error: String?
    @Published var isImporting = false

    func importFile(_ url: URL, sourceLabel: String? = nil) {
        guard !isImporting else { return }
        isImporting = true; error = nil
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    // Read while scoped access is active; retain only the parsed session model.
                    return try LandXMLParser().parse(url: url)
                }.value
                project = imported; source = sourceLabel ?? url.lastPathComponent
            } catch { self.error = error.localizedDescription }
            isImporting = false
        }
    }
    #if DEBUG
    func loadSample(_ sample: SampleFile) {
        guard let url = Bundle.main.url(forResource: sample.name, withExtension: "xml") else {
            error = "Bundled sample is missing: \(sample.name).xml"; return
        }
        importFile(url, sourceLabel: "Synthetic sample • \(sample.name).xml")
    }
    #endif
}

#if DEBUG
struct SampleFile: Identifiable {
    let name: String
    let title: String
    var id: String { name }
    static let all: [SampleFile] = [
        .init(name: "tangent-only", title: "Tangent • synthetic"),
        .init(name: "spiral-curve-spiral", title: "Spiral / curve / spiral • synthetic"),
        .init(name: "station-equations", title: "Station equations • synthetic"),
        .init(name: "multiple-alignments", title: "Multiple alignments • synthetic"),
        .init(name: "sr82_synthetic", title: "Large projected coordinates • synthetic")
    ]
}
#endif

@MainActor
final class WorkspaceModel: ObservableObject {
    let alignment: RoadStationCore.Alignment
    let unit: ProjectUnit
    @Published var polylines: [AlignmentPolyline] = []
    @Published var queryPoint: ProjectCoordinate?
    @Published var result: StationOffsetResult?
    @Published var inverseResult: CoordinateResult?
    @Published var inverseNearestPoint: ProjectCoordinate?
    @Published var error: String?
    @Published var busy = false
    @Published var branches: [StationLocation] = []
    @Published var plotRevision = 0
    @Published var samplingError: String?

    var bounds: SegmentBounds {
        let boxes = alignment.segments.map(\.bounds)
        return SegmentBounds(points: boxes.flatMap {
            [ProjectCoordinate(x: $0.minX, y: $0.minY), .init(x: $0.maxX, y: $0.maxY)]
        })
    }
    init(alignment: RoadStationCore.Alignment, unit: ProjectUnit) { self.alignment = alignment; self.unit = unit }
    func loadDrawing() async {
        guard polylines.isEmpty, samplingError == nil else { return }
        do {
            let a = alignment
            polylines = try await Task.detached(priority: .userInitiated) {
                try AlignmentSampling.polylines(alignment: a)
            }.value
        } catch { samplingError = error.localizedDescription }
    }
    func inspect(_ point: ProjectCoordinate, fit: Bool = false) {
        guard !busy else { return }
        busy = true; error = nil; branches = []; result = nil; inverseResult = nil; inverseNearestPoint = nil; queryPoint = point
        Task {
            let a = alignment
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try AlignmentEngine(alignment: a).stationOffset(point: point)
                }.value
                if fit { plotRevision += 1 }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func inspect(easting: String, northing: String) {
        do { inspect(try ManualQuery.coordinate(easting: easting, northing: northing), fit: true) }
        catch { self.error = error.localizedDescription }
    }
    func inverse(station text: String, magnitude: String, side: EntrySide, branch: Int? = nil) {
        guard !busy else { return }
        error = nil; result = nil; inverseResult = nil; inverseNearestPoint = nil; queryPoint = nil; branches = []
        do {
            let station = try ManualQuery.station(text)
            let offset = try ManualQuery.signedOffset(magnitude: magnitude, side: side)
            // Resolve through the core; no UI-selected default equation branch.
            if branch == nil, case .ambiguous(let candidates) = StationingEngine(alignment: alignment).resolve(station: station) {
                branches = candidates
                error = "Station is ambiguous. Choose an equation branch below; no point has been calculated."
                return
            }
            let a = alignment
            busy = true
            Task {
                do {
                    let values = try await Task.detached(priority: .userInitiated) {
                        let engine = AlignmentEngine(alignment: a)
                        let inverse = try engine.coordinate(station: station, offset: offset, branchIndex: branch)
                        let nearest = try engine.point(at: inverse.geometricDistance).point
                        do {
                            return (inverse, nearest, Optional(try engine.stationOffset(point: inverse.coordinate)), Optional<String>.none)
                        } catch {
                            // An optional forward check must not discard a valid inverse.
                            return (inverse, nearest, Optional<StationOffsetResult>.none, Optional(error.localizedDescription))
                        }
                    }.value
                    inverseResult = values.0; inverseNearestPoint = values.1; result = values.2; queryPoint = values.0.coordinate
                    if let message = values.3 { error = "Coordinate calculated; forward inspection unavailable: " + message }
                    plotRevision += 1
                } catch { self.error = error.localizedDescription }
                busy = false
            }
        } catch { self.error = error.localizedDescription }
    }
}

func numeric(_ value: Double, decimals: Int = 6) -> String {
    value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
        .precision(.fractionLength(decimals)))
}
func sideLabel(_ side: OffsetSide) -> String {
    switch side { case .left: "LT"; case .right: "RT"; case .onAlignment: "ON" }
}
