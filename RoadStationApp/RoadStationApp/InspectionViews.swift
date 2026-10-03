import SwiftUI
import RoadStationCore

struct AlignmentInfo: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        EngineeringCard {
            Text("Alignment information").font(.headline)
            LabeledContent("Name", value: model.alignment.name)
            LabeledContent("Start station", value: StationFormatter.string(model.alignment.startStation))
            LabeledContent("Horizontal length", value: numeric(model.alignment.totalGeometricLength))
            LabeledContent("Units", value: unitName(model.unit))
            LabeledContent("Segments", value: String(model.alignment.segments.count))
            LabeledContent("Lines", value: String(count("Line")))
            LabeledContent("Circular curves", value: String(count("Circular curve")))
            LabeledContent("Spirals", value: String(count("Clothoid")))
                .accessibilityElement(children: .combine).accessibilityIdentifier("spiral-count").accessibilityValue(String(count("Clothoid")))
            LabeledContent("Station equations", value: String(model.alignment.stationEquations.count))
            if let description = model.alignment.metadata.description { Text(description).font(.footnote) }
            if let source = model.alignment.metadata.sourceIdentifier { LabeledContent("Source ID", value: source) }
            if let declared = model.alignment.metadata.declaredLength { LabeledContent("Declared length", value: numeric(declared)) }
            Divider()
            Text("Alignment warnings").font(.headline)
            if model.alignment.warnings.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(Array(model.alignment.warnings.enumerated()), id: \.offset) { _, text in Text(text).font(.footnote) }
            Divider()
            ForEach(Array(model.alignment.segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index). \(segment.geometry.typeName)").font(.subheadline.bold())
                    Text("Distance \(numeric(segment.geometricStartDistance, decimals: 3)) → \(numeric(segment.geometricEndDistance, decimals: 3))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.alignment.stationEquations.isEmpty {
                Divider(); Text("Equation branches").font(.headline)
                ForEach(Array(model.alignment.stationEquations.enumerated()), id: \.offset) { index, equation in
                    Text("\(index) → \(index + 1): distance \(numeric(equation.geometricDistance))\nBack \(StationFormatter.string(equation.stationBack, precision: 6)) • Ahead \(StationFormatter.string(equation.stationAhead, precision: 6))")
                        .font(.caption).monospacedDigit()
                }
            }
        }.font(.subheadline).monospacedDigit().textSelection(.enabled)
    }
    private func count(_ type: String) -> Int { model.alignment.segments.filter { $0.geometry.typeName == type }.count }
}

struct RawInspection: View {
    @ObservedObject var model: WorkspaceModel
    var body: some View {
        EngineeringCard {
            Text("Developer inspection").font(.headline)
            Text("Raw core values for manual comparison. No ORD expected values are supplied.").font(.caption).foregroundStyle(.secondary)
            if let r = model.result, let q = model.queryPoint {
                LabeledContent("Query E", value: numeric(q.x, decimals: 9))
                LabeledContent("Query N", value: numeric(q.y, decimals: 9))
                LabeledContent("Geometric distance", value: numeric(r.geometricDistance, decimals: 9))
                LabeledContent("Raw station", value: numeric(r.displayedStation, decimals: 9))
                LabeledContent("Formatted station", value: StationFormatter.string(r.displayedStation, precision: 6))
                LabeledContent("Signed offset", value: numeric(r.signedOffset, decimals: 9))
                LabeledContent("Side", value: sideLabel(r.side))
                LabeledContent("Segment index (0-based)", value: String(r.nearestSegmentIndex))
                LabeledContent("Segment type", value: r.segmentType)
                LabeledContent("Tangent X", value: numeric(r.tangent.x, decimals: 12))
                LabeledContent("Tangent Y", value: numeric(r.tangent.y, decimals: 12))
                LabeledContent("Bearing (CW from N, rad)", value: numeric(r.bearing, decimals: 12))
                LabeledContent("Nearest E", value: numeric(r.nearestPoint.x, decimals: 9))
                LabeledContent("Nearest N", value: numeric(r.nearestPoint.y, decimals: 9))
                LabeledContent("Query distance", value: numeric(r.distanceFromQueryPointToAlignment, decimals: 9))
                LabeledContent("Longitudinal residual", value: numeric(r.longitudinalResidual, decimals: 9))
                LabeledContent("Ambiguous", value: r.nearestLocationIsAmbiguous ? "TRUE — representative only" : "false")
                    .foregroundStyle(r.nearestLocationIsAmbiguous ? .red : .primary)
            } else { Text("Make a query first.").foregroundStyle(.secondary) }
        }.font(.caption).monospacedDigit().textSelection(.enabled)
    }
}
