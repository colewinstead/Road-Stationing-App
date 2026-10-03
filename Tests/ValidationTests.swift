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
    func testMalformedCaseJSONThrows() { XCTAssertThrowsError(try ValidationRunner.loadJSON(Data("[{]".utf8))) }
}
