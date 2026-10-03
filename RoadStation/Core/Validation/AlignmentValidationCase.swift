import Foundation

public enum ValidationDirection: String, Codable, Sendable { case forward, inverse }
/// Numeric station values and positive-left offsets in source project units.
/// Expected results must be supplied independently, e.g. by ORD or Civil 3D.
public struct AlignmentValidationCase: Codable, Sendable {
    public let id: String
    public let alignmentName: String
    public let referenceSource: String
    public let direction: ValidationDirection
    public let inputCoordinate: ProjectCoordinate?
    public let inputStation: Double?
    public let inputOffset: Double?
    public let branchIndex: Int?
    public let expectedCoordinate: ProjectCoordinate?
    public let expectedStation: Double?
    public let expectedOffset: Double?
    public let stationTolerance: Double
    public let offsetTolerance: Double
    public let coordinateTolerance: Double
    public init(id: String, alignmentName: String, referenceSource: String, direction: ValidationDirection,
                inputCoordinate: ProjectCoordinate? = nil, inputStation: Double? = nil, inputOffset: Double? = nil,
                branchIndex: Int? = nil, expectedCoordinate: ProjectCoordinate? = nil,
                expectedStation: Double? = nil, expectedOffset: Double? = nil,
                stationTolerance: Double = 0.001, offsetTolerance: Double = 0.001, coordinateTolerance: Double = 0.001) {
        self.id = id; self.alignmentName = alignmentName; self.referenceSource = referenceSource; self.direction = direction
        self.inputCoordinate = inputCoordinate; self.inputStation = inputStation; self.inputOffset = inputOffset
        self.branchIndex = branchIndex; self.expectedCoordinate = expectedCoordinate
        self.expectedStation = expectedStation; self.expectedOffset = expectedOffset
        self.stationTolerance = stationTolerance; self.offsetTolerance = offsetTolerance; self.coordinateTolerance = coordinateTolerance
    }
}

public struct AlignmentValidationResult: Codable, Sendable {
    public let validationCase: AlignmentValidationCase
    public let passed: Bool
    public let actualStation: Double?
    public let actualOffset: Double?
    public let actualCoordinate: ProjectCoordinate?
    public let stationDifference: Double?
    public let offsetDifference: Double?
    public let coordinateDifference: Double?
    public let error: String?
}
