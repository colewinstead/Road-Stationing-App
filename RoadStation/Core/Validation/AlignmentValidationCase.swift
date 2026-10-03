import Foundation

public enum ValidationSide: String, Codable, Sendable { case LT, RT, ON }
public enum ValidationCategory: String, Codable, Sendable { case line, curve, spiral, stationEquation }

public enum ValidationDirection: String, Codable, Sendable { case forward, inverse }
/// Numeric station values and positive-left offsets in source project units.
/// Expected results must be supplied independently, e.g. by ORD or Civil 3D.
public struct AlignmentValidationCase: Codable, Sendable {
    public let id: String
    public let alignmentName: String
    public let referenceSource: String
    public let referenceSoftware: String?
    public let referenceSoftwareVersion: String?
    public let sourceLandXML: String?
    public let description: String?
    public let category: ValidationCategory?
    /// When supplied, offsets are nonnegative magnitudes paired with LT/RT/ON.
    /// When absent, offsets retain the original positive-left signed convention.
    public let inputSide: ValidationSide?
    public let expectedSide: ValidationSide?
    /// Forward equation-limit comparison; inverse selects a branch with branchIndex.
    public let equationSide: EquationSide?
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
                stationTolerance: Double = 0.001, offsetTolerance: Double = 0.001, coordinateTolerance: Double = 0.001,
                referenceSoftware: String? = nil, referenceSoftwareVersion: String? = nil,
                sourceLandXML: String? = nil, description: String? = nil, category: ValidationCategory? = nil,
                inputSide: ValidationSide? = nil, expectedSide: ValidationSide? = nil, equationSide: EquationSide? = nil) {
        self.id = id; self.alignmentName = alignmentName; self.referenceSource = referenceSource; self.direction = direction
        self.referenceSoftware = referenceSoftware; self.referenceSoftwareVersion = referenceSoftwareVersion
        self.sourceLandXML = sourceLandXML; self.description = description; self.category = category
        self.inputSide = inputSide; self.expectedSide = expectedSide; self.equationSide = equationSide
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
    public let actualSide: ValidationSide?
    public let actualCoordinate: ProjectCoordinate?
    public let stationDifference: Double?
    public let offsetDifference: Double?
    public let coordinateDifference: Double?
    public let error: String?
}
