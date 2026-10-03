import Foundation
import XCTest
@testable import RoadStationCore

final class ValidationTests: XCTestCase {
    func testJSONForwardAndInverseCasesPass() throws {
        let cases = try ValidationRunner.loadJSON(TestSupport.fixture("validation-cases.json"))
        let result = try ValidationRunner.run(cases: cases, alignments: [TestSupport.alignment("tangent-only.xml")])
        XCTAssertEqual(result.count, 2); XCTAssertTrue(result.allSatisfy(\.passed))
        XCTAssertEqual(result[0].stationDifference!, 0, accuracy: 1e-12)
        XCTAssertEqual(result[1].coordinateDifference!, 0, accuracy: 1e-12)
    }
    func testNumericalFailureNotFalsePass() throws {
        let c = AlignmentValidationCase(id: "fail", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 50, y: -5), expectedStation: 10051, expectedOffset: -6)
        let r = try ValidationRunner.run(cases: [c], alignments: [TestSupport.lineAlignment()])[0]
        XCTAssertFalse(r.passed); XCTAssertEqual(r.stationDifference!, -1, accuracy: 1e-12)
        XCTAssertEqual(r.offsetDifference!, 1, accuracy: 1e-12); XCTAssertNil(r.error)
    }
    func testMissingInputsFailWithDiagnostic() throws {
        let c = AlignmentValidationCase(id: "missing", alignmentName: "Test", referenceSource: "analytic", direction: .forward)
        let r = try ValidationRunner.run(cases: [c], alignments: [TestSupport.lineAlignment()])[0]
        XCTAssertFalse(r.passed); XCTAssertTrue(r.error!.contains("requires"))
    }
    func testAmbiguousInverseFailsUnlessBranchSpecified() throws {
        let a = try TestSupport.lineAlignment(equations: [.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10050)])
        let c = AlignmentValidationCase(id: "ambiguous", alignmentName: "Test", referenceSource: "analytic", direction: .inverse,
            inputStation: 10075, inputOffset: 5, expectedCoordinate: .init(x: 125, y: 5))
        let r = ValidationRunner.run(cases: [c], alignments: [a])[0]
        XCTAssertFalse(r.passed); XCTAssertTrue(r.error!.contains("ambiguous"))
        let resolved = AlignmentValidationCase(id: "resolved", alignmentName: "Test", referenceSource: "analytic", direction: .inverse,
            inputStation: 10075, inputOffset: 5, branchIndex: 1, expectedCoordinate: .init(x: 125, y: 5))
        XCTAssertTrue(ValidationRunner.run(cases: [resolved], alignments: [a])[0].passed)
    }
    func testDuplicateAlignmentNameIsError() throws {
        let c = AlignmentValidationCase(id: "duplicate", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 0, y: 0), expectedStation: 10000, expectedOffset: 0)
        let a = try TestSupport.lineAlignment(); let r = ValidationRunner.run(cases: [c], alignments: [a, a])[0]
        XCTAssertFalse(r.passed); XCTAssertTrue(r.error!.contains("exactly one"))
    }
    func testNegativeToleranceRejected() throws {
        let c = AlignmentValidationCase(id: "bad", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 0, y: 0), expectedStation: 10000, expectedOffset: 0, stationTolerance: -1)
        XCTAssertFalse(try ValidationRunner.run(cases: [c], alignments: [TestSupport.lineAlignment()])[0].passed)
    }
    func testJSONExportRetainsCaseAndDifferences() throws {
        let cases = try ValidationRunner.loadJSON(TestSupport.fixture("validation-cases.json"))
        let results = try ValidationRunner.run(cases: cases, alignments: [TestSupport.alignment("tangent-only.xml")])
        let data = try ValidationExporter.json(results)
        let decoded = try JSONDecoder().decode([AlignmentValidationResult].self, from: data)
        XCTAssertEqual(decoded[0].validationCase.referenceSource, cases[0].referenceSource)
        XCTAssertEqual(decoded[1].actualCoordinate!.y, 1990, accuracy: 1e-12)
    }
    func testCSVQuotingAndNewlines() throws {
        let c = AlignmentValidationCase(id: "quote,\"test", alignmentName: "Test", referenceSource: "A\nB", direction: .forward,
            inputCoordinate: .init(x: 50, y: 5), expectedStation: 10050, expectedOffset: 5)
        let results = try ValidationRunner.run(cases: [c], alignments: [TestSupport.lineAlignment()])
        let csv = ValidationExporter.csv(results)
        XCTAssertTrue(csv.contains("\"quote,\"\"test\"")); XCTAssertTrue(csv.contains("\"A\nB\""))
        XCTAssertTrue(csv.hasSuffix("\r\n")); XCTAssertTrue(csv.contains("\"PASS\""))
    }
    func testORDMetadataAndSideMagnitudeSurviveJSONAndCSV() throws {
        let c = AlignmentValidationCase(id: "ORD", alignmentName: "Test", referenceSource: "DGN revision / report",
            direction: .forward, inputCoordinate: .init(x: 50, y: -5), expectedStation: 10050, expectedOffset: 5,
            referenceSoftware: "OpenRoads Designer", referenceSoftwareVersion: "recorded-version",
            sourceLandXML: "real-export.xml", description: "Tangent RT", category: .line, expectedSide: .RT)
        let decoded = try ValidationRunner.loadJSON(JSONEncoder().encode([c]))
        let results = try ValidationRunner.run(cases: decoded, alignments: [TestSupport.lineAlignment()])
        XCTAssertTrue(results[0].passed); XCTAssertEqual(results[0].actualSide, .RT)
        let roundTrip = try JSONDecoder().decode([AlignmentValidationResult].self, from: ValidationExporter.json(results))
        XCTAssertEqual(roundTrip[0].validationCase.sourceLandXML, "real-export.xml")
        XCTAssertEqual(roundTrip[0].validationCase.referenceSoftwareVersion, "recorded-version")
        let csv = ValidationExporter.csv(results)
        XCTAssertTrue(csv.contains("\"referenceSoftwareVersion\"")); XCTAssertTrue(csv.contains("\"real-export.xml\""))
    }
    func testInverseSideMagnitudeAndExistingSignedOffsetAgree() throws {
        let side = AlignmentValidationCase(id: "side", alignmentName: "Test", referenceSource: "analytic", direction: .inverse,
            inputStation: 10050, inputOffset: 5, expectedCoordinate: .init(x: 50, y: -5), inputSide: .RT)
        let signed = AlignmentValidationCase(id: "signed", alignmentName: "Test", referenceSource: "analytic", direction: .inverse,
            inputStation: 10050, inputOffset: -5, expectedCoordinate: .init(x: 50, y: -5))
        let results = try ValidationRunner.run(cases: [side, signed], alignments: [TestSupport.lineAlignment()])
        XCTAssertTrue(results.allSatisfy(\.passed))
        XCTAssertEqual(results[0].actualCoordinate, results[1].actualCoordinate)
    }
    func testSideMismatchAndConflictingSignedMagnitudeFail() throws {
        let wrongSide = AlignmentValidationCase(id: "wrong-side", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 50, y: 5), expectedStation: 10050, expectedOffset: 5, offsetTolerance: 20, expectedSide: .RT)
        let conflict = AlignmentValidationCase(id: "conflict", alignmentName: "Test", referenceSource: "analytic", direction: .inverse,
            inputStation: 10050, inputOffset: -5, expectedCoordinate: .init(x: 50, y: -5), inputSide: .RT)
        let results = try ValidationRunner.run(cases: [wrongSide, conflict], alignments: [TestSupport.lineAlignment()])
        XCTAssertFalse(results[0].passed); XCTAssertFalse(results[1].passed)
        XCTAssertTrue(results[1].error!.contains("nonnegative"))
    }
    func testRoundedZeroOffsetWithinValidationToleranceClassifiesON() throws {
        let c = AlignmentValidationCase(id: "rounded", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 50, y: 0.0000005), expectedStation: 10050, expectedOffset: 0, expectedSide: .ON)
        XCTAssertTrue(try ValidationRunner.run(cases: [c], alignments: [TestSupport.lineAlignment()])[0].passed)
    }
    func testExplicitForwardEquationLimitsRetainRoundingResidual() throws {
        let a = try TestSupport.lineAlignment(equations: [.init(geometricDistance: 100, stationBack: 10100, stationAhead: 10200)])
        let back = AlignmentValidationCase(id: "back", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 100.0001, y: 0), expectedStation: 10100, expectedOffset: 0, equationSide: .back)
        let ahead = AlignmentValidationCase(id: "ahead", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 99.9999, y: 0), expectedStation: 10200, expectedOffset: 0, equationSide: .ahead)
        let far = AlignmentValidationCase(id: "far", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 99, y: 0), expectedStation: 10100, expectedOffset: 0, equationSide: .back)
        let results = ValidationRunner.run(cases: [back, ahead, far], alignments: [a])
        XCTAssertTrue(results[0].passed); XCTAssertEqual(results[0].stationDifference!, 0.0001, accuracy: 1e-10)
        XCTAssertTrue(results[1].passed); XCTAssertEqual(results[1].stationDifference!, -0.0001, accuracy: 1e-10)
        XCTAssertFalse(results[2].passed); XCTAssertTrue(results[2].error!.contains("one equation"))
    }
    func testSummaryIncludesFailedNumericComparisonsAndMissingMetrics() throws {
        let c = AlignmentValidationCase(id: "wrong", alignmentName: "Test", referenceSource: "analytic", direction: .forward,
            inputCoordinate: .init(x: 50, y: -5), expectedStation: 10051, expectedOffset: -7)
        let missing = AlignmentValidationCase(id: "missing", alignmentName: "Test", referenceSource: "analytic", direction: .forward)
        let results = try ValidationRunner.run(cases: [c, missing], alignments: [TestSupport.lineAlignment()])
        let summary = ValidationSummary(results: results)
        XCTAssertEqual(summary.cases, 2); XCTAssertEqual(summary.failed, 2)
        XCTAssertEqual(summary.maximumStationError, 1); XCTAssertEqual(summary.maximumOffsetError, 2)
        XCTAssertNil(summary.maximumCoordinateError); XCTAssertTrue(summary.text.contains("N/A"))
    }
    func testORDTemplateContainsAllUnpopulatedSlotsAndCannotPass() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Validation/ORD-validation-template.json"))
        let cases = try ValidationRunner.loadJSON(data)
        XCTAssertEqual(cases.count, 32)
        XCTAssertEqual(Set(cases.map(\.id)).count, 32)
        XCTAssertEqual(cases.filter { $0.direction == .forward }.count, 16)
        XCTAssertTrue(cases.allSatisfy { $0.expectedStation == nil && $0.expectedCoordinate == nil && $0.expectedOffset == nil })
        let a = try Alignment(name: "__FILL_EXACT_ORD_ALIGNMENT_NAME__", geometries: [.line(LineSegment(start: .init(x: 0, y: 0), end: .init(x: 100, y: 0)))])
        XCTAssertTrue(ValidationRunner.run(cases: cases, alignments: [a]).allSatisfy { !$0.passed })
    }
    func testMalformedCaseJSONThrows() { XCTAssertThrowsError(try ValidationRunner.loadJSON(Data("[{]".utf8))) }
}
