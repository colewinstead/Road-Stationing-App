import Foundation
import XCTest
import CoreLocation
import Combine
import Dispatch
import RoadStationCore
import RoadStationAppleCRS
import RoadStationCRSCatalog
@testable import RoadStationFieldPosition

@MainActor
private final class FakeLocationService: LocationProviding {
    var permission: LocationPermission = .authorized
    var preciseAccuracy = true
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    var requests = 0; var starts = 0; var stops = 0
    func requestPermission() { requests += 1 }
    func start() { starts += 1 }
    func stop() { stops += 1 }
}
@MainActor
private final class FakeRecommendationService: RecommendationLocationProviding {
    var permission: LocationPermission = .authorized
    var preciseAccuracy = true
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    var prompts = 0, fixes = 0, cancellations = 0
    func requestPermission() { prompts += 1 }
    func requestLocation() { fixes += 1 }
    func cancelRequest() { cancellations += 1 }
}
@MainActor
private final class FakeRecommendationManager: RecommendationLocationManaging {
    var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var desiredAccuracy: CLLocationAccuracy = 0
    var prompts = 0, fixes = 0, stops = 0, continuousStarts = 0, alwaysPrompts = 0
    func requestWhenInUseAuthorization() { prompts += 1 }
    func requestLocation() { fixes += 1 }
    func stopUpdatingLocation() { stops += 1 }
    func startUpdatingLocation() { continuousStarts += 1 }
    func requestAlwaysAuthorization() { alwaysPrompts += 1 }
}
private struct FailedTransformer: ProjectCoordinateTransformer {
    let definition: ResolvedCRS
    func projectCoordinate(from coordinate: GeographicCoordinate) throws -> ProjectCoordinate {
        throw CoordinateTransformationError.transformationFailed("Injected backend failure")
    }
    func geographicCoordinate(from coordinate: ProjectCoordinate) throws -> GeographicCoordinate {
        throw CoordinateTransformationError.transformationFailed("Injected backend failure")
    }
}
/// Holds validation off actor until the test has delivered a concurrent event.
private final class ValidationGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func wait() { entered.signal(); resume.wait() }
    func didEnter() -> Bool { entered.wait(timeout: .now() + 5) == .success }
}
private final class TransformationCounter: @unchecked Sendable {
    private let lock = NSCondition()
    private var calls = 0
    func record() { lock.withLock { calls += 1; lock.broadcast() } }
    var count: Int { lock.withLock { calls } }
    func receivedCalls(_ target: Int) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        lock.lock(); defer { lock.unlock() }
        while calls < target { if !lock.wait(until: deadline) { return false } }
        return true
    }
}
/// Test-only scheduling control around the real transformer. No GPS throttling
/// or altered station/offset calculations are introduced in production.
private struct ControlledTransformer: ProjectCoordinateTransformer {
    let base: PROJProjectCoordinateTransformer
    let gates: [Double: ValidationGate]
    let failures: Set<Double>
    let counter: TransformationCounter?
    var definition: ResolvedCRS { base.definition }
    func projectCoordinate(from coordinate: GeographicCoordinate) throws -> ProjectCoordinate {
        counter?.record()
        gates[coordinate.longitude]?.wait()
        if failures.contains(coordinate.longitude) {
            throw CoordinateTransformationError.transformationFailed("Injected subsequent failure")
        }
        return try base.projectCoordinate(from: coordinate)
    }
    func geographicCoordinate(from coordinate: ProjectCoordinate) throws -> GeographicCoordinate {
        try base.geographicCoordinate(from: coordinate)
    }
}
final class FieldPositionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    // Independently published NGA EPSG:3857 point for 1E,1N.
    private let e = 111319.49079327357, n = 111325.14286638486
    private func alignment(y: Double? = nil, name: String = "TEST") throws -> Alignment {
        try Alignment(name: name, startStation: 4346.42,
            geometries: [.line(LineSegment(start: .init(x: e - 50, y: y ?? n - 5),
                                          end: .init(x: e + 50, y: y ?? n - 5)))])
    }
    private func project(unit: ProjectUnit = .meter, imported: Bool = false) throws -> Project {
        Project(name: "test", unit: unit, alignments: [try alignment()],
            crsResolution: imported ? .identified(try CoordinateReferenceSystem(epsgCode: 3857)) : .unresolved(.missingIdentification))
    }
    private func sample(age: Double = 0, accuracy: Double = 3, latitude: Double = 1, longitude: Double = 1) -> LocationSample {
        LocationSample(latitude: latitude, longitude: longitude, horizontalAccuracyMeters: accuracy,
                       timestamp: now.addingTimeInterval(-age))
    }
    @MainActor private func makeSession(service: FakeLocationService = FakeLocationService(), unit: ProjectUnit = .meter) async throws -> FieldPositionSession {
        let session = FieldPositionSession(service: service)
        session.load(project: try project(unit: unit))
        await session.selectEPSG("3857", now: now)
        await session.selectAlignment(try alignment(), now: now)
        session.start(now: now.addingTimeInterval(-1))
        return session
    }
    @MainActor private func controlledSession(service: FakeLocationService = FakeLocationService(),
                                             gates: [Double: ValidationGate], failures: Set<Double> = [],
                                             counter: TransformationCounter? = nil) async throws -> FieldPositionSession {
        let session = FieldPositionSession(service: service, factory: { resolution, unit in
            ControlledTransformer(base: try PROJProjectCoordinateTransformer(resolution: resolution, outputUnit: .linear(unit)),
                                  gates: gates, failures: failures, counter: counter)
        })
        session.load(project: try project()); await session.selectEPSG("3857", now: now)
        await session.selectAlignment(try alignment(), now: now); session.start(now: now.addingTimeInterval(-1))
        return session
    }
    @MainActor func testPickerPreviewRecommendationsAndOpeningNeverConfirmOrRequestPermission() async throws {
        let service = FakeLocationService(); service.permission = .notDetermined
        let session = FieldPositionSession(service: service); session.load(project: try project())
        let picker = CRSPickerModel(); await picker.load()
        let entry = try XCTUnwrap(picker.catalog?.entry(code: 6510))
        picker.preview(entry)
        XCTAssertEqual(picker.pending, entry); XCTAssertNil(session.confirmedCRS)
        let recommendation = LocationSample(latitude: 32.3, longitude: -90.2, horizontalAccuracyMeters: 3, timestamp: now)
        XCTAssertFalse(picker.recommendations(sample: recommendation, permission: .authorized, policy: session.policy, unit: .usSurveyFoot, now: now).isEmpty)
        XCTAssertNil(session.confirmedCRS); XCTAssertEqual(service.requests, 0); XCTAssertEqual(service.starts, 0)
        picker.cancelPreview(); XCTAssertNil(picker.pending); XCTAssertNil(session.confirmedCRS)
        picker.preview(entry); await picker.confirm(in: session)
        XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 6510)
        XCTAssertEqual(session.confirmedCRS?.provenance, .catalog)
        XCTAssertEqual(session.confirmedCRS?.definition.outputUnit, .linear(.meter))
        XCTAssertEqual(service.requests, 0)
    }
    @MainActor func testPickerPreservesImportedCRSAndItsConfirmationProvenance() async throws {
        let session = FieldPositionSession(service: FakeLocationService()); let original = try project(imported: true)
        session.load(project: original)
        let picker = CRSPickerModel(); await picker.load()
        picker.preview(try XCTUnwrap(picker.catalog?.entry(code: 6510)))
        XCTAssertEqual(session.project?.crsResolution, original.crsResolution); XCTAssertNil(session.confirmedCRS)
        await session.confirmImportedCRS(now: now)
        XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 3857)
        XCTAssertEqual(session.confirmedCRS?.provenance, .landXML)
        picker.cancelPreview(); XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 3857)
    }
    @MainActor func testPickerExplicitCRSChangeInvalidatesPriorLivePosition() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample()), now: now); XCTAssertNotNil(session.fieldPosition)
        // Make the retained raw sample ineligible, so CRS change cannot immediately
        // produce another valid snapshot under the new definition.
        session.refresh(now: now.addingTimeInterval(6))
        await session.confirmCatalogCRS(code: 6510, now: now.addingTimeInterval(6))
        XCTAssertNil(session.fieldPosition); XCTAssertEqual(session.confirmedCRS?.provenance, .catalog)
        XCTAssertEqual(session.project?.crsResolution, .unresolved(.missingIdentification))
        await session.selectEPSG("3857", now: now.addingTimeInterval(6))
        XCTAssertEqual(session.confirmedCRS?.provenance, .manual)
    }
    @MainActor func testRecommendationFreshnessPermissionPoorAccuracyAndDebugLocation() async throws {
        let picker = CRSPickerModel(); await picker.load()
        let policy = LocationQualityPolicy()
        let fix = LocationSample(latitude: 32.3, longitude: -90.2, horizontalAccuracyMeters: 30, timestamp: now)
        XCTAssertNil(CRSPickerModel.recommendationPoint(sample: nil, permission: .authorized, policy: policy, now: now))
        XCTAssertNil(CRSPickerModel.recommendationPoint(sample: fix, permission: .denied, policy: policy, now: now))
        XCTAssertTrue(picker.recommendations(sample: fix, permission: .authorized, policy: policy, unit: .usSurveyFoot, now: now.addingTimeInterval(6)).isEmpty)
        XCTAssertEqual(policy.quality(of: fix, now: now), .poorAccuracy)
        XCTAssertEqual(picker.recommendations(sample: fix, permission: .authorized, policy: policy, unit: .usSurveyFoot, now: now).first?.entry.code, 6510)
        let debug = LocationSample(latitude: 32.3, longitude: -90.2, horizontalAccuracyMeters: 30, timestamp: now, source: .developerInjection)
        XCTAssertNotNil(CRSPickerModel.recommendationPoint(sample: debug, permission: .denied, policy: policy, now: now))
        XCTAssertNil(CRSPickerModel.recommendationPoint(sample: debug, permission: .denied, policy: policy, now: now.addingTimeInterval(6)))
        let invalid = LocationSample(latitude: 100, longitude: -90.2, horizontalAccuracyMeters: 30, timestamp: now)
        XCTAssertNil(CRSPickerModel.recommendationPoint(sample: invalid, permission: .authorized, policy: policy, now: now))
    }
    @MainActor func testAreaWarningDoesNotChangeImportedOrSelectedCRS() async throws {
        let picker = CRSPickerModel(); await picker.load()
        let entry = try XCTUnwrap(picker.catalog?.entry(code: 6510))
        let outside = sample(latitude: 40, longitude: -120)
        let session = FieldPositionSession(service: FakeLocationService()); session.load(project: try project(imported: true))
        await session.confirmImportedCRS(now: now)
        let original = session.confirmedCRS
        XCTAssertNotNil(CRSPickerModel.outsideAreaWarning(entry: entry, sample: outside, permission: .authorized, policy: session.policy, now: now))
        XCTAssertEqual(session.confirmedCRS, original)
        XCTAssertNil(CRSPickerModel.outsideAreaWarning(entry: entry, sample: outside, permission: .authorized, policy: session.policy, now: now.addingTimeInterval(6)))
        let inside = LocationSample(latitude: 32.3, longitude: -90.2, horizontalAccuracyMeters: 30, timestamp: now)
        XCTAssertNil(CRSPickerModel.outsideAreaWarning(entry: entry, sample: inside, permission: .authorized, policy: session.policy, now: now))
    }
    @MainActor func testPickerSearchUsesCatalogAndLatestQuery() async throws {
        let picker = CRSPickerModel(); await picker.load()
        await picker.search("Mississippi West")
        XCTAssertTrue(picker.searchResults.contains { $0.code == 6510 })
        await picker.search("nothing-matches-XYZ"); XCTAssertTrue(picker.searchResults.isEmpty)
    }
    @MainActor func testFirstCalculationCanShowLoadingWithoutSnapshot() async throws {
        let gate = ValidationGate(); defer { gate.resume.signal() }
        let session = try await controlledSession(gates: [1: gate])
        let calculation = Task { await session.handle(.sample(sample()), now: now) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered)
        XCTAssertTrue(session.isCalculating); XCTAssertEqual(session.status, .calculating)
        XCTAssertNil(session.fieldPosition)
        gate.resume.signal(); await calculation.value
        XCTAssertNotNil(session.fieldPosition); XCTAssertFalse(session.isCalculating)
    }
    @MainActor func testNextCalculationPreservesAndAtomicallyReplacesSnapshot() async throws {
        let gate = ValidationGate(); defer { gate.resume.signal() }
        let session = try await controlledSession(gates: [1.0001: gate])
        await session.handle(.sample(sample()), now: now)
        let first = try XCTUnwrap(session.fieldPosition)
        var publications: [FieldPositionSnapshot?] = []
        let observation = session.$fieldPosition.dropFirst().sink { publications.append($0) }
        let calculation = Task { await session.handle(.sample(sample(age: -0.1, accuracy: 4, longitude: 1.0001)), now: now) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered)
        XCTAssertTrue(session.isCalculating); XCTAssertEqual(session.fieldPosition, first)
        XCTAssertEqual(session.status, .locationReady)
        XCTAssertEqual(session.accuracyInProjectUnits(), 3, "Do not mix new accuracy with the old station")
        XCTAssertTrue(publications.isEmpty, "Starting an update must not publish a cleared/partial snapshot")
        gate.resume.signal(); await calculation.value
        let next = try XCTUnwrap(session.fieldPosition)
        XCTAssertEqual(publications.count, 1); XCTAssertEqual(publications.first!, next)
        XCTAssertEqual(next.sample.longitude, 1.0001); XCTAssertEqual(next.sample.timestamp, now.addingTimeInterval(0.1))
        XCTAssertEqual(next.accuracyInProjectUnits, 4)
        XCTAssertEqual(next.coordinate.x, e * 1.0001, accuracy: 1e-7)
        XCTAssertEqual(next.result.displayedStation, 4396.42 + e * 0.0001, accuracy: 1e-7)
        XCTAssertEqual(next.alignmentName, "TEST"); XCTAssertEqual(next.crs.definition.crs.epsgCode, 3857)
        XCTAssertEqual(next.unit, .meter); XCTAssertEqual(next.status, .locationReady)
        XCTAssertFalse(session.isCalculating)
        withExtendedLifetime(observation) {}
    }
    @MainActor func testSubsequentFailureRetainsLastKnownSnapshot() async throws {
        let gate = ValidationGate(); defer { gate.resume.signal() }
        let session = try await controlledSession(gates: [1.0001: gate], failures: [1.0001])
        await session.handle(.sample(sample()), now: now)
        let first = try XCTUnwrap(session.fieldPosition)
        var publications: [FieldPositionSnapshot?] = []
        let observation = session.$fieldPosition.dropFirst().sink { publications.append($0) }
        let calculation = Task { await session.handle(.sample(sample(age: -0.1, longitude: 1.0001)), now: now) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered); XCTAssertEqual(session.fieldPosition, first); XCTAssertTrue(publications.isEmpty)
        gate.resume.signal(); await calculation.value
        // A failed update cannot replace a successful last-known position.
        guard case .transformationFailure = session.status else { return XCTFail("Expected failure policy") }
        XCTAssertTrue(publications.isEmpty)
        XCTAssertEqual(session.fieldPosition, first); XCTAssertFalse(session.isCalculating)
        XCTAssertEqual(session.displayedPositionMessage, "Last known position — update unavailable.")
        withExtendedLifetime(observation) {}
    }
    @MainActor func testOutOfOrderCompletionCannotOverwriteNewerSnapshot() async throws {
        let older = ValidationGate(); defer { older.resume.signal() }
        let session = try await controlledSession(gates: [1.0001: older])
        await session.handle(.sample(sample()), now: now)
        let pending = Task { await session.handle(.sample(sample(age: -0.1, longitude: 1.0001)), now: now) }
        let entered = await Task.detached { older.didEnter() }.value
        XCTAssertTrue(entered)
        await session.handle(.sample(sample(age: -0.2, longitude: 1.0002)), now: now)
        let newest = try XCTUnwrap(session.fieldPosition)
        XCTAssertEqual(newest.sample.longitude, 1.0002)
        older.resume.signal(); await pending.value
        XCTAssertEqual(session.fieldPosition, newest); XCTAssertFalse(session.isCalculating)
        // An older timestamp is also ignored at receipt, not just completion.
        await session.handle(.sample(sample(age: -0.1, longitude: 1.0003)), now: now)
        XCTAssertEqual(session.fieldPosition, newest)
    }
    @MainActor func testSupersededCompletionCannotStopNewerCalculationActivity() async throws {
        let older = ValidationGate(), newer = ValidationGate()
        defer { older.resume.signal(); newer.resume.signal() }
        let session = try await controlledSession(gates: [1.0001: older, 1.0002: newer])
        await session.handle(.sample(sample()), now: now)
        let first = try XCTUnwrap(session.fieldPosition)
        let oldTask = Task { await session.handle(.sample(sample(age: -0.1, longitude: 1.0001)), now: now) }
        let oldEntered = await Task.detached { older.didEnter() }.value
        XCTAssertTrue(oldEntered)
        let newTask = Task { await session.handle(.sample(sample(age: -0.2, longitude: 1.0002)), now: now) }
        let newEntered = await Task.detached { newer.didEnter() }.value
        XCTAssertTrue(newEntered)
        older.resume.signal(); await oldTask.value
        XCTAssertTrue(session.isCalculating); XCTAssertEqual(session.fieldPosition, first)
        newer.resume.signal(); await newTask.value
        XCTAssertEqual(session.fieldPosition?.sample.longitude, 1.0002); XCTAssertFalse(session.isCalculating)
    }
    @MainActor func testDisplayedFixBecomesStaleWithoutCancelingFreshPendingCalculation() async throws {
        let gate = ValidationGate(); defer { gate.resume.signal() }
        let session = try await controlledSession(gates: [1.0001: gate])
        await session.handle(.sample(sample()), now: now)
        let first = try XCTUnwrap(session.fieldPosition)
        let calculation = Task { await session.handle(.sample(sample(age: -4, longitude: 1.0001)), now: now.addingTimeInterval(4)) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered); XCTAssertNotNil(session.fieldPosition)
        session.refresh(now: now.addingTimeInterval(6))
        XCTAssertEqual(session.fieldPosition, first); XCTAssertTrue(session.isCalculating)
        XCTAssertTrue(session.displayedPositionIsStale)
        XCTAssertEqual(session.displayedPositionMessage, "Stale — last known position")
        gate.resume.signal(); await calculation.value
        XCTAssertEqual(session.fieldPosition?.sample.longitude, 1.0001)
        XCTAssertEqual(session.status, .locationReady)
        XCTAssertFalse(session.displayedPositionIsStale)
    }
    @MainActor func testStaleSnapshotRetainedWithoutCalculationThenFreshFixReplacesItOnce() async throws {
        let counter = TransformationCounter()
        let session = try await controlledSession(gates: [:], counter: counter)
        await session.handle(.sample(sample()), now: now)
        let first = try XCTUnwrap(session.fieldPosition)
        var publications: [FieldPositionSnapshot?] = []
        var staleTransitions = 0
        let snapshots = session.$fieldPosition.dropFirst().sink { publications.append($0) }
        let freshness = session.$displayedPositionIsStale.dropFirst().sink { if $0 { staleTransitions += 1 } }
        session.refresh(now: now.addingTimeInterval(5))
        XCTAssertFalse(session.displayedPositionIsStale)
        session.refresh(now: now.addingTimeInterval(5.01))
        XCTAssertEqual(session.fieldPosition, first); XCTAssertEqual(session.status, .staleLocation)
        XCTAssertTrue(session.displayedPositionIsStale)
        XCTAssertEqual(session.displayedPositionMessage, "Stale — last known position")
        for seconds in 6...12 { session.refresh(now: now.addingTimeInterval(Double(seconds))) }
        XCTAssertEqual(session.fieldPosition, first); XCTAssertTrue(publications.isEmpty)
        XCTAssertEqual(staleTransitions, 1); XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(first.age(at: now.addingTimeInterval(12)), 12)
        // Receiving another stale sample must not start a new transform/station query.
        let stale = sample(longitude: 1.0001)
        XCTAssertEqual(session.policy.quality(of: stale, now: now.addingTimeInterval(12)), .stale)
        await session.handle(.sample(stale), now: now.addingTimeInterval(12))
        XCTAssertEqual(counter.count, 1); XCTAssertEqual(session.fieldPosition, first)
        XCTAssertTrue(publications.isEmpty); XCTAssertFalse(session.isCalculating)
        await session.handle(.sample(sample(age: -12, accuracy: 4, longitude: 1.0002)), now: now.addingTimeInterval(12))
        let next = try XCTUnwrap(session.fieldPosition)
        XCTAssertEqual(counter.count, 2); XCTAssertEqual(publications.count, 1)
        XCTAssertEqual(publications.first!, next)
        XCTAssertEqual(next.sample.timestamp, now.addingTimeInterval(12)); XCTAssertEqual(next.accuracyInProjectUnits, 4)
        XCTAssertEqual(next.coordinate.x, e * 1.0002, accuracy: 1e-7)
        XCTAssertEqual(next.result.displayedStation, 4396.42 + e * 0.0002, accuracy: 1e-7)
        XCTAssertFalse(session.displayedPositionIsStale); XCTAssertEqual(session.status, .locationReady)
        XCTAssertEqual(session.displayedPositionMessage, "Location ready.")
        session.stop(); XCTAssertNil(session.fieldPosition)
        withExtendedLifetime((snapshots, freshness)) {}
    }
    @MainActor func testEveryRapidLocationServiceCallbackIsProcessedWithoutDebounce() async throws {
        let service = FakeLocationService(), counter = TransformationCounter()
        let session = try await controlledSession(service: service, gates: [:], counter: counter)
        // Same fresh timestamp keeps this callback-delivery test independent of
        // actor task ordering; older-timestamp rejection has its own regression.
        let timestamp = Date()
        for index in 0..<8 {
            service.onEvent?(.sample(LocationSample(latitude: 1, longitude: 1 + Double(index) * 0.000001,
                horizontalAccuracyMeters: 3, timestamp: timestamp)))
        }
        let received = await Task.detached { counter.receivedCalls(8) }.value
        XCTAssertTrue(received); XCTAssertEqual(counter.count, 8)
        withExtendedLifetime(session) {}
    }
    @MainActor func testPermissionStatesAndOnlyExplicitRequest() async throws {
        for (permission, expected) in [(LocationPermission.notDetermined, FieldPositionStatus.waitingForPermission),
                                      (.denied, .permissionDenied), (.restricted, .permissionRestricted), (.authorized, .waitingForLocation)] {
            let service = FakeLocationService(); service.permission = permission
            let session = try await makeSession(service: service)
            XCTAssertEqual(session.status, expected)
            XCTAssertEqual(service.requests, permission == .notDetermined ? 1 : 0)
            XCTAssertNil(session.result)
        }
    }
    @MainActor func testPermissionGrantRevocationAndReducedAccuracy() async throws {
        let service = FakeLocationService(); service.permission = .notDetermined
        let session = try await makeSession(service: service)
        await session.handle(.permission(.authorized, precise: false), now: now)
        await session.handle(.sample(sample()), now: now)
        XCTAssertEqual(session.status, .poorAccuracy); XCTAssertNotNil(session.result)
        await session.handle(.permission(.denied, precise: false), now: now)
        XCTAssertEqual(session.status, .permissionDenied); XCTAssertNil(session.result)
        await session.handle(.sample(sample()), now: now)
        XCTAssertNil(session.result)
        XCTAssertGreaterThan(service.stops, 0)
    }
    @MainActor func testKnownWGS84ProjectionStationOffsetPipeline() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample()), now: now)
        XCTAssertEqual(session.status, .locationReady)
        let point = try XCTUnwrap(session.coordinate)
        XCTAssertEqual(point.x, e, accuracy: 1e-7); XCTAssertEqual(point.y, n, accuracy: 1e-7)
        let result = try XCTUnwrap(session.result)
        XCTAssertEqual(result.displayedStation, 4396.42, accuracy: 1e-7)
        XCTAssertEqual(result.signedOffset, 5, accuracy: 1e-7); XCTAssertEqual(result.side, .left)
        XCTAssertEqual(result.formattedStation, "43+96.42")
        XCTAssertEqual(session.accuracyInProjectUnits(), 3)
        XCTAssertNotNil(session.projectionMilliseconds)
    }
    @MainActor func testStaleCachedFixAndTimerExpiry() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample(age: 0.5)), now: now)
        XCTAssertNotNil(session.result)
        var staleNotifications = 0
        let observation = session.$status.sink { if $0 == .staleLocation { staleNotifications += 1 } }
        session.refresh(now: now.addingTimeInterval(6))
        XCTAssertEqual(session.status, .staleLocation); XCTAssertNotNil(session.result)
        for seconds in 7...10 { session.refresh(now: now.addingTimeInterval(Double(seconds))) }
        XCTAssertEqual(staleNotifications, 1, "Repeated stale refresh must not republish and restart UI refresh")
        withExtendedLifetime(observation) {}
        await session.handle(.sample(sample(age: 20)), now: now)
        XCTAssertEqual(session.status, .staleLocation)
        // A fresh fix can recover; stale state never permanently disables updates.
        await session.handle(.sample(sample()), now: now)
        XCTAssertNotNil(session.result)
        session.start(now: now.addingTimeInterval(1))
        await session.handle(.sample(sample()), now: now.addingTimeInterval(1))
        XCTAssertEqual(session.status, .staleLocation); XCTAssertNil(session.result)
    }
    @MainActor func testNegativeAndNonFiniteAccuracy() async throws {
        for value in [-1.0, .nan, .infinity] {
            let session = try await makeSession()
            await session.handle(.sample(sample(accuracy: value)), now: now)
            XCTAssertEqual(session.status, .invalidAccuracy); XCTAssertNil(session.result)
            XCTAssertNil(session.accuracyInProjectUnits())
        }
    }
    @MainActor func testPoorAccuracyIsRetainedAndCanRecover() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample(accuracy: 50)), now: now)
        XCTAssertEqual(session.status, .poorAccuracy); XCTAssertNotNil(session.result)
        XCTAssertEqual(session.sample?.horizontalAccuracyMeters, 50)
        await session.handle(.sample(sample()), now: now)
        XCTAssertEqual(session.status, .locationReady)
    }
    @MainActor func testInvalidCoordinatesAndFutureTimestamp() async throws {
        for (lat, lon) in [(Double.nan, 1.0), (1, .infinity), (91, 0), (0, 181)] {
            let session = try await makeSession()
            await session.handle(.sample(sample(latitude: lat, longitude: lon)), now: now)
            XCTAssertEqual(session.status, .invalidCoordinate); XCTAssertNil(session.result)
        }
        let session = try await makeSession()
        await session.handle(.sample(sample(age: -10)), now: now)
        XCTAssertEqual(session.status, .invalidTimestamp)
        await session.handle(.sample(sample()), now: now)
        XCTAssertEqual(session.status, .locationReady)
    }
    @MainActor func testCRSUnresolvedAndImportedConfirmationProvenance() async throws {
        let service = FakeLocationService(); let session = FieldPositionSession(service: service)
        session.load(project: try project())
        XCTAssertEqual(session.status, .crsRequired); XCTAssertNil(session.confirmedCRS)
        session.start(now: now); XCTAssertEqual(service.requests, 0)
        session.load(project: try project(imported: true))
        XCTAssertEqual(session.status, .crsConfirmationRequired)
        await session.confirmImportedCRS(now: now)
        XCTAssertEqual(session.confirmedCRS?.provenance, .landXML)
        await session.selectEPSG("32632", now: now)
        XCTAssertEqual(session.confirmedCRS?.provenance, .manual)
        XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 32632)
        XCTAssertEqual(session.project?.crsResolution, .identified(try CoordinateReferenceSystem(epsgCode: 3857)))
    }
    @MainActor func testInvalidAndUnsupportedEPSGSelectionsClearOldResult() async throws {
        for text in ["", "-1", "0", "EPSG:banana", "+3857", "999999", "2147483648"] {
            let session = try await makeSession()
            await session.handle(.sample(sample()), now: now)
            await session.selectEPSG(text, now: now)
            guard case .crsUnavailable = session.status else { return XCTFail("Expected CRS failure: \(text)") }
            XCTAssertNil(session.confirmedCRS); XCTAssertNil(session.result)
        }
    }
    @MainActor func testUnitCompatibilityAndDistinctAccuracyConversion() async throws {
        let service = FakeLocationService(); let session = FieldPositionSession(service: service)
        session.load(project: try project())
        await session.selectEPSG("4326", now: now)
        guard case .crsUnavailable = session.status else { return XCTFail("Degrees cannot be used as linear project coordinates") }
        session.load(project: try project(unit: .unknown))
        await session.selectEPSG("3857", now: now)
        XCTAssertNil(session.confirmedCRS)
        for unit in [ProjectUnit.internationalFoot, .usSurveyFoot] {
            let session = try await makeSession(unit: unit)
            await session.handle(.sample(sample()), now: now)
            XCTAssertEqual(try XCTUnwrap(session.accuracyInProjectUnits()), 3 / unit.metersPerUnit!, accuracy: 1e-10)
            XCTAssertEqual(session.confirmedCRS?.definition.outputUnit, .linear(unit))
        }
    }
    @MainActor func testTransformationFailureIsVisible() async throws {
        let service = FakeLocationService()
        let session = FieldPositionSession(service: service, factory: { resolution, unit in
            guard case .identified(let crs) = resolution else { throw CoordinateTransformationError.unsupportedUnits }
            return FailedTransformer(definition: ResolvedCRS(crs: crs, nativeUnit: .linear(unit), outputUnit: .linear(unit)))
        })
        session.load(project: try project()); await session.selectEPSG("3857", now: now)
        await session.selectAlignment(try alignment(), now: now); session.start(now: now.addingTimeInterval(-1))
        await session.handle(.sample(sample()), now: now)
        guard case .transformationFailure(let detail) = session.status else { return XCTFail("Expected transformation failure") }
        XCTAssertTrue(detail.contains("Injected backend failure")); XCTAssertNil(session.result)
    }
    @MainActor func testAmbiguityRemainsVisibleEvenWithPoorGPS() async throws {
        let session = try await makeSession()
        let repeated = try Alignment(name: "repeated", geometries: [
            .line(LineSegment(start: .init(x: e - 50, y: n - 5), end: .init(x: e + 50, y: n - 5))),
            .line(LineSegment(start: .init(x: e - 50, y: n - 5), end: .init(x: e + 50, y: n - 5)))])
        await session.selectAlignment(repeated, now: now)
        await session.handle(.sample(sample(accuracy: 50)), now: now)
        XCTAssertEqual(session.status, .ambiguousLocation)
        XCTAssertTrue(try XCTUnwrap(session.result).nearestLocationIsAmbiguous)
    }
    @MainActor func testAlignmentAndCRSChangesRecomputeLatestLocation() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample()), now: now)
        let original = try XCTUnwrap(session.coordinate)
        await session.selectAlignment(try alignment(y: n + 5, name: "OTHER"), now: now)
        XCTAssertEqual(session.alignment?.name, "OTHER")
        XCTAssertEqual(try XCTUnwrap(session.result).signedOffset, -5, accuracy: 1e-7)
        await session.selectEPSG("32631", now: now)
        XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 32631)
        XCTAssertNotEqual(session.coordinate, original)
        await session.handle(.sample(sample(latitude: 1.001)), now: now)
        XCTAssertNotNil(session.result)
    }
    @MainActor func testLocationCallbackDoesNotCancelCRSValidation() async throws {
        let gate = ValidationGate()
        let session = FieldPositionSession(service: FakeLocationService(), factory: { resolution, unit in
            if case .identified(let crs) = resolution, crs.epsgCode == 32631 { gate.wait() }
            return try PROJProjectCoordinateTransformer(resolution: resolution, outputUnit: .linear(unit))
        })
        session.load(project: try project()); await session.selectEPSG("3857", now: now)
        await session.selectAlignment(try alignment(), now: now); session.start(now: now.addingTimeInterval(-1))
        let selection = Task { await session.selectEPSG("32631", now: now) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered)
        await session.handle(.sample(sample(latitude: 1.002)), now: now)
        XCTAssertEqual(session.status, .calculating)
        gate.resume.signal(); await selection.value
        XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 32631)
        XCTAssertEqual(session.sample?.latitude, 1.002)
        XCTAssertEqual(session.status, .locationReady); XCTAssertNotNil(session.result)
    }
    @MainActor func testNewProjectDiscardsPendingCRSValidation() async throws {
        let gate = ValidationGate()
        let session = FieldPositionSession(service: FakeLocationService(), factory: { resolution, unit in
            gate.wait()
            return try PROJProjectCoordinateTransformer(resolution: resolution, outputUnit: .linear(unit))
        })
        session.load(project: try project())
        let selection = Task { await session.selectEPSG("3857", now: now) }
        let entered = await Task.detached { gate.didEnter() }.value
        XCTAssertTrue(entered)
        session.load(project: try project())
        gate.resume.signal(); await selection.value
        XCTAssertNil(session.confirmedCRS); XCTAssertNil(session.result)
        XCTAssertEqual(session.status, .crsRequired)
    }
    @MainActor func testStopOldCallbacksAndLocationFailure() async throws {
        let session = try await makeSession()
        await session.handle(.sample(sample()), now: now)
        await session.handle(.failure("Location temporarily unknown"), now: now)
        XCTAssertEqual(session.status, .locationFailure("Location temporarily unknown")); XCTAssertNotNil(session.result)
        await session.handle(.sample(sample()), now: now); XCTAssertNotNil(session.result)
        session.stop(); XCTAssertEqual(session.status, .stopped); XCTAssertNil(session.result)
        await session.handle(.sample(sample()), now: now); XCTAssertNil(session.sample)
    }
    func testCLLocationBoundaryAndSpeedCourseValidation() {
        XCTAssertEqual(CoreLocationService.permission(.notDetermined), .notDetermined)
        #if os(iOS)
        XCTAssertEqual(CoreLocationService.permission(.authorizedWhenInUse), .authorized)
        #endif
        XCTAssertEqual(CoreLocationService.permission(.authorizedAlways), .authorized)
        XCTAssertEqual(CoreLocationService.permission(.denied), .denied)
        XCTAssertEqual(CoreLocationService.permission(.restricted), .restricted)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 99,
                                  horizontalAccuracy: -1, verticalAccuracy: 10, timestamp: now)
        let sample = CoreLocationService.sample(location)
        XCTAssertEqual(sample.latitude, 1); XCTAssertEqual(sample.longitude, 2)
        XCTAssertEqual(sample.horizontalAccuracyMeters, -1); XCTAssertEqual(sample.timestamp, now)
        XCTAssertNil(sample.speedMetersPerSecond); XCTAssertNil(sample.courseDegrees)
        let invalid = LocationSample(latitude: 1, longitude: 2, horizontalAccuracyMeters: 1, timestamp: now,
                                     speedMetersPerSecond: .nan, courseDegrees: 360)
        XCTAssertNil(invalid.speedMetersPerSecond); XCTAssertNil(invalid.courseDegrees)
        let valid = LocationSample(latitude: 1, longitude: 2, horizontalAccuracyMeters: 1, timestamp: now,
                                   speedMetersPerSecond: 12, courseDegrees: 90)
        XCTAssertEqual(valid.speedMetersPerSecond, 12); XCTAssertEqual(valid.courseDegrees, 90)
    }
    func testQualityThresholdsAreConfigurable() {
        XCTAssertEqual(LocationQualityPolicy().quality(of: sample(age: 5, accuracy: 10), now: now), .usable)
        XCTAssertEqual(LocationQualityPolicy().quality(of: sample(age: 5.01), now: now), .stale)
        XCTAssertEqual(LocationQualityPolicy(maximumAgeSeconds: 10, warningAccuracyMeters: 2).quality(of: sample(age: 6), now: now), .poorAccuracy)
    }
    #if DEBUG
    @MainActor func testDebugInjectionUsesSamePipelineWithoutDevicePermission() async throws {
        let service = FakeLocationService(); service.permission = .denied
        let session = try await makeSession(service: service)
        await session.inject(sample(), now: now)
        XCTAssertEqual(session.status, .locationReady); XCTAssertEqual(session.sample?.source, .developerInjection)
        XCTAssertEqual(try XCTUnwrap(session.result).displayedStation, 4396.42, accuracy: 1e-7)
        XCTAssertEqual(service.requests, 0)
        session.refresh(now: now.addingTimeInterval(6)); XCTAssertNotNil(session.result)
        XCTAssertTrue(session.displayedPositionIsStale)
    }
    #endif
    @MainActor func testAuthorizedPickerRequestsOneFixOnOpeningWithoutPermissionPrompt() {
        let service = FakeRecommendationService()
        // Reopening callbacks on the same presentation must not duplicate a request.
        let active = CRSPickerModel(locationService: service)
        active.openRecommendationLocation(); active.openRecommendationLocation()
        XCTAssertEqual(active.recommendationStatus, .finding); XCTAssertNil(active.recommendationLocation)
        XCTAssertEqual(service.fixes, 1); XCTAssertEqual(service.prompts, 0)
    }
    @MainActor func testUndeterminedPickerRequiresActionThenWhenInUsePermissionBeforeFix() {
        let service = FakeRecommendationService(); service.permission = .notDetermined
        let picker = CRSPickerModel(locationService: service); picker.openRecommendationLocation()
        XCTAssertEqual(picker.recommendationStatus, .needsPermission)
        XCTAssertEqual(service.prompts, 0); XCTAssertEqual(service.fixes, 0)
        picker.handleRecommendationEvent(.permission(.notDetermined, precise: true), now: now)
        picker.useMyLocation(); picker.useMyLocation()
        XCTAssertEqual(picker.recommendationStatus, .waitingForPermission)
        XCTAssertEqual(service.prompts, 1); XCTAssertEqual(service.fixes, 0)
        service.permission = .authorized
        picker.handleRecommendationEvent(.permission(.authorized, precise: true), now: now)
        picker.handleRecommendationEvent(.permission(.authorized, precise: true), now: now)
        XCTAssertEqual(service.fixes, 1); XCTAssertEqual(picker.recommendationStatus, .finding)
    }
    @MainActor func testDeniedAndRestrictedPickerNeverPromptAndKeepCatalogAvailable() async {
        for permission in [LocationPermission.denied, .restricted] {
            let service = FakeRecommendationService(); service.permission = permission
            let picker = CRSPickerModel(locationService: service); picker.openRecommendationLocation()
            await picker.load(); await picker.search("6510")
            picker.useMyLocation(); picker.useMyLocation()
            XCTAssertEqual(picker.recommendationStatus, permission == .denied ? .denied : .restricted)
            XCTAssertEqual(service.fixes, 0); XCTAssertEqual(service.prompts, 0)
            XCTAssertEqual(picker.searchResults.first?.code, 6510); XCTAssertNil(picker.recommendationLocation)
        }
    }
    @MainActor func testPermissionDeniedAfterActionDoesNotRequestFix() {
        let service = FakeRecommendationService(); service.permission = .notDetermined
        let picker = CRSPickerModel(locationService: service); picker.openRecommendationLocation(); picker.useMyLocation()
        service.permission = .denied
        picker.handleRecommendationEvent(.permission(.denied, precise: false), now: now)
        XCTAssertEqual(picker.recommendationStatus, .denied); XCTAssertEqual(service.fixes, 0)
        picker.useMyLocation(); XCTAssertEqual(service.prompts, 1)
    }
    @MainActor func testOneShotFailureOnlyRetriesOnExplicitActionAndIgnoresClosedCallbacks() {
        let service = FakeRecommendationService(); let picker = CRSPickerModel(locationService: service)
        picker.openRecommendationLocation(); picker.handleRecommendationEvent(.failure("No fix"), now: now)
        XCTAssertEqual(picker.recommendationStatus, .failed("No fix")); XCTAssertNil(picker.recommendationLocation)
        XCTAssertEqual(service.fixes, 1)
        picker.useMyLocation(); XCTAssertEqual(service.fixes, 2)
        picker.closeRecommendationLocation()
        picker.handleRecommendationEvent(.sample(sample()), now: now)
        picker.handleRecommendationEvent(.permission(.authorized, precise: true), now: now)
        XCTAssertNil(picker.recommendationLocation); XCTAssertEqual(service.fixes, 2)
        XCTAssertEqual(service.cancellations, 1)
    }
    @MainActor func testFreshOneShotGeneratesRetainedRecommendationsWithoutConfirmingCRS() async throws {
        let service = FakeRecommendationService(); let picker = CRSPickerModel(locationService: service)
        let live = FakeLocationService(); let session = FieldPositionSession(service: live)
        session.load(project: try project(unit: .usSurveyFoot)); let status = session.status, stops = live.stops
        await picker.load(); picker.openRecommendationLocation()
        let fix = sample(latitude: 32.3, longitude: -90.2)
        var publications = 0
        let observer = picker.$recommendationLocation.dropFirst().sink { _ in publications += 1 }
        picker.handleRecommendationEvent(.sample(fix), now: now)
        let snapshot = try XCTUnwrap(picker.recommendationLocation)
        XCTAssertEqual(snapshot.sample, fix); XCTAssertFalse(snapshot.isApproximate)
        XCTAssertEqual(picker.recommendationStatus, .ready)
        let recommendations = picker.capturedRecommendations(unit: .usSurveyFoot)
        XCTAssertEqual(recommendations.first?.entry.code, 6510)
        // No periodic refresh/expiry operation is needed for a captured recommendation.
        for seconds in [5.01, 60, 3600] {
            XCTAssertEqual(LocationQualityPolicy().quality(of: fix, now: now.addingTimeInterval(seconds)), .stale)
            XCTAssertEqual(picker.capturedRecommendations(unit: .usSurveyFoot).map(\.entry.code), recommendations.map(\.entry.code))
            XCTAssertEqual(picker.recommendationLocation, snapshot)
        }
        XCTAssertEqual(publications, 1); withExtendedLifetime(observer) {}
        picker.preview(try XCTUnwrap(recommendations.first?.entry))
        XCTAssertNil(session.confirmedCRS); XCTAssertNil(session.fieldPosition); XCTAssertNil(session.sample)
        XCTAssertEqual(session.status, status); XCTAssertFalse(session.isRunning)
        XCTAssertEqual(live.starts, 0); XCTAssertEqual(live.requests, 0); XCTAssertEqual(live.stops, stops)
    }
    @MainActor func testPoorAndReducedAccuracyOneShotsStillRecommendWithApproximateWarning() async throws {
        for (accuracy, precise) in [(100.0, true), (3.0, false)] {
            let service = FakeRecommendationService(); service.preciseAccuracy = precise
            let picker = CRSPickerModel(locationService: service); await picker.load(); picker.openRecommendationLocation()
            picker.handleRecommendationEvent(.sample(sample(accuracy: accuracy, latitude: 32.3, longitude: -90.2)), now: now)
            let snapshot = try XCTUnwrap(picker.recommendationLocation)
            XCTAssertTrue(snapshot.isApproximate); XCTAssertEqual(snapshot.sample.horizontalAccuracyMeters, accuracy)
            XCTAssertFalse(picker.capturedRecommendations(unit: .meter).isEmpty)
        }
    }
    @MainActor func testInitiallyStaleAndInvalidOneShotFixesAreRejected() {
        for invalid in [sample(age: 5.01), sample(accuracy: -1), sample(latitude: .nan), sample(longitude: .infinity)] {
            let picker = CRSPickerModel(locationService: FakeRecommendationService()); picker.openRecommendationLocation()
            picker.handleRecommendationEvent(.sample(invalid), now: now)
            guard case .failed = picker.recommendationStatus else { return XCTFail("Expected acquisition quality failure") }
            XCTAssertNil(picker.recommendationLocation)
        }
    }
    @MainActor func testRefreshFailureRetainsCapturedSnapshotUntilCompletedReplacement() throws {
        let service = FakeRecommendationService(); let picker = CRSPickerModel(locationService: service)
        picker.openRecommendationLocation(); picker.handleRecommendationEvent(.sample(sample()), now: now)
        let previous = try XCTUnwrap(picker.recommendationLocation)
        picker.useMyLocation(); XCTAssertEqual(picker.recommendationStatus, .finding)
        XCTAssertEqual(picker.recommendationLocation, previous)
        picker.handleRecommendationEvent(.failure("Unavailable"), now: now)
        XCTAssertEqual(picker.recommendationLocation, previous)
        picker.useMyLocation()
        let next = sample(age: -1, latitude: 2)
        picker.handleRecommendationEvent(.sample(next), now: now.addingTimeInterval(1))
        XCTAssertEqual(picker.recommendationLocation?.sample, next); XCTAssertEqual(picker.recommendationStatus, .ready)
    }
    @MainActor func testRecommendationDoesNotAlterActiveFieldPositionOrPerformStationing() async throws {
        let live = FakeLocationService(), counter = TransformationCounter()
        let session = try await controlledSession(service: live, gates: [:], counter: counter)
        await session.handle(.sample(sample()), now: now)
        let snapshot = session.fieldPosition, fix = session.sample, status = session.status, crs = session.confirmedCRS
        let calls = counter.count, starts = live.starts, stops = live.stops
        let service = FakeRecommendationService(); let picker = CRSPickerModel(locationService: service)
        picker.openRecommendationLocation(); picker.handleRecommendationEvent(.sample(sample(latitude: 32.3, longitude: -90.2)), now: now)
        picker.closeRecommendationLocation()
        XCTAssertTrue(session.isRunning); XCTAssertEqual(session.fieldPosition, snapshot)
        XCTAssertEqual(session.sample, fix); XCTAssertEqual(session.status, status)
        XCTAssertEqual(session.confirmedCRS, crs); XCTAssertEqual(counter.count, calls)
        XCTAssertEqual(live.starts, starts); XCTAssertEqual(live.stops, stops); XCTAssertEqual(live.requests, 0)
    }
    @MainActor func testProductionRecommendationAdapterUsesRequestLocationForBothAuthorizations() {
        var permissions: [CLAuthorizationStatus] = [.authorizedAlways]
        #if os(iOS)
        permissions.append(.authorizedWhenInUse)
        #endif
        let callbackManager = CLLocationManager()
        for permission in permissions {
            let manager = FakeRecommendationManager(); manager.authorizationStatus = permission
            let service = CoreLocationRecommendationService(manager: manager)
            var events: [LocationEvent] = []
            service.onEvent = { events.append($0) }
            service.requestPermission(); service.requestLocation(); service.requestLocation()
            XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyBestForNavigation)
            XCTAssertEqual(manager.fixes, 1); XCTAssertEqual(manager.prompts, 0)
            let older = CLLocation(coordinate: .init(latitude: 1, longitude: 2), altitude: 0,
                horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: now)
            let newer = CLLocation(coordinate: .init(latitude: 3, longitude: 4), altitude: 0,
                horizontalAccuracy: 6, verticalAccuracy: -1, timestamp: now.addingTimeInterval(1))
            service.locationManager(callbackManager, didUpdateLocations: [newer, older])
            service.locationManager(callbackManager, didUpdateLocations: [older])
            XCTAssertEqual(events.count, 1)
            if case .sample(let fix) = events.first { XCTAssertEqual(fix.latitude, 3) } else { XCTFail("Missing fix") }
            service.requestLocation(); service.cancelRequest()
            service.locationManager(callbackManager, didUpdateLocations: [newer])
            XCTAssertEqual(events.count, 1); XCTAssertEqual(manager.stops, 1)
            XCTAssertEqual(manager.continuousStarts, 0); XCTAssertEqual(manager.alwaysPrompts, 0)
        }
    }
    @MainActor func testProductionRecommendationPermissionAndFailureCalls() {
        let manager = FakeRecommendationManager(); manager.authorizationStatus = .notDetermined
        let service = CoreLocationRecommendationService(manager: manager), callbackManager = CLLocationManager()
        service.requestLocation(); XCTAssertEqual(manager.fixes, 0)
        service.requestPermission(); XCTAssertEqual(manager.prompts, 1); XCTAssertEqual(manager.alwaysPrompts, 0)
        let picker = CRSPickerModel(locationService: service); picker.openRecommendationLocation(); picker.useMyLocation()
        manager.authorizationStatus = .authorizedAlways
        service.locationManagerDidChangeAuthorization(callbackManager)
        XCTAssertEqual(manager.fixes, 1); XCTAssertEqual(picker.recommendationStatus, .finding)
        service.locationManager(callbackManager, didFailWithError: NSError(domain: "test", code: 1))
        guard case .failed = picker.recommendationStatus else { return XCTFail("Failure must reach the picker") }
        service.locationManager(callbackManager, didUpdateLocations: [CLLocation(latitude: 1, longitude: 2)])
        XCTAssertNil(picker.recommendationLocation)
        XCTAssertEqual(manager.continuousStarts, 0)
    }
    #if DEBUG
    @MainActor func testRecommendationDebugInjectionCancelsPendingDeviceFixAndRetainsCapture() {
        let service = FakeRecommendationService(); let picker = CRSPickerModel(locationService: service)
        picker.openRecommendationLocation(); picker.injectRecommendation(sample(), now: now)
        XCTAssertEqual(service.cancellations, 1); XCTAssertEqual(picker.recommendationLocation?.sample.source, .developerInjection)
        picker.handleRecommendationEvent(.sample(sample(latitude: 2)), now: now)
        XCTAssertEqual(picker.recommendationLocation?.point.latitude, 1)
        XCTAssertEqual(picker.recommendationStatus, .ready)
    }
    #endif

    @MainActor func testSavedConfirmationRestoresAllProvenanceWithoutStartingLocationOrStationing() async throws {
        for provenance in [CRSSelectionProvenance.landXML, .manual, .catalog] {
            let service = FakeLocationService(); service.permission = .notDetermined
            let counter = TransformationCounter()
            let session = FieldPositionSession(service: service, factory: { resolution, unit in
                ControlledTransformer(base: try PROJProjectCoordinateTransformer(resolution: resolution, outputUnit: .linear(unit)),
                    gates: [:], failures: [], counter: counter)
            })
            session.load(project: try project())
            await session.restoreConfirmedCRS(code: 3857, provenance: provenance, now: now)
            await session.selectAlignment(try alignment(), now: now)
            XCTAssertEqual(session.confirmedCRS?.provenance, provenance)
            XCTAssertEqual(session.confirmedCRS?.definition.crs.epsgCode, 3857)
            XCTAssertFalse(session.isRunning); XCTAssertNil(session.fieldPosition); XCTAssertNil(session.sample)
            XCTAssertEqual(service.requests, 0); XCTAssertEqual(service.starts, 0); XCTAssertEqual(counter.count, 0)
            await session.restoreConfirmedCRS(code: -1, provenance: provenance, now: now)
            XCTAssertNil(session.confirmedCRS); XCTAssertFalse(session.isRunning)
            XCTAssertEqual(service.requests, 0); XCTAssertEqual(service.starts, 0); XCTAssertEqual(counter.count, 0)
        }
    }

}
