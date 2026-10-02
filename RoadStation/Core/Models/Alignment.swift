import Foundation

public struct AlignmentMetadata: Sendable {
    public let description: String?
    public let sourceIdentifier: String?
    public let declaredLength: Double?
    public init(description: String? = nil, sourceIdentifier: String? = nil, declaredLength: Double? = nil) {
        self.description = description; self.sourceIdentifier = sourceIdentifier; self.declaredLength = declaredLength
    }
}

public struct Alignment: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let startStation: Double
    public let segments: [AlignmentSegment]
    public let stationEquations: [StationEquation]
    public let totalGeometricLength: Double
    public let metadata: AlignmentMetadata
    public let warnings: [String]

    public init(id: UUID = UUID(), name: String, startStation: Double = 0,
                geometries: [SegmentGeometry], stationEquations: [StationEquation] = [],
                metadata: AlignmentMetadata = AlignmentMetadata(), warnings: [String] = [],
                tolerances: GeometryTolerances = .standard) throws {
        guard startStation.isFinite, !geometries.isEmpty else {
            throw GeometryError.invalidGeometry("Alignment must have geometry and finite start station.")
        }
        var segments: [AlignmentSegment] = []; var distance = 0.0; var notes = warnings
        for geometry in geometries {
            if let previous = segments.last, previous.end.distance(to: geometry.start) > tolerances.continuity {
                notes.append("Disconnected geometry at segment \(segments.count + 1): gap \(previous.end.distance(to: geometry.start)) project units.")
            }
            segments.append(AlignmentSegment(geometry: geometry, geometricStartDistance: distance))
            distance += geometry.length
        }
        guard distance.isFinite else { throw GeometryError.invalidGeometry("Total length overflow.") }
        let equations = stationEquations.sorted { $0.geometricDistance < $1.geometricDistance }
        try StationingEngine.validate(equations: equations, startStation: startStation, length: distance, tolerances: tolerances)
        if let declared = metadata.declaredLength, abs(declared - distance) > tolerances.importConsistency {
            notes.append("Declared alignment length \(declared) differs from horizontal geometric length \(distance).")
        }
        self.id = id; self.name = name; self.startStation = startStation; self.segments = segments
        self.stationEquations = equations; self.totalGeometricLength = distance
        self.metadata = metadata; self.warnings = notes
    }
}
