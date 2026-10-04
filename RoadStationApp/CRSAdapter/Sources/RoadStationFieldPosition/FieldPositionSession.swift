import Foundation
import Combine
import RoadStationCore
import RoadStationAppleCRS

/// Session-only state. Main actor owns selection/service/UI; projection and exact
/// geometry execute off actor. Revision checks prevent superseded work publishing.
@MainActor
public final class FieldPositionSession: ObservableObject {
    public typealias TransformerFactory = @Sendable (CRSResolution, ProjectUnit) throws -> any ProjectCoordinateTransformer
    @Published public private(set) var status: FieldPositionStatus = .crsRequired
    @Published public private(set) var confirmedCRS: ConfirmedProjectCRS?
    @Published public private(set) var sample: LocationSample?
    @Published public private(set) var fieldPosition: FieldPositionSnapshot?
    @Published public private(set) var isCalculating = false
    @Published public private(set) var displayedPositionIsStale = false
    public var displayedPositionMessage: String {
        guard let fieldPosition else { return status.message }
        if displayedPositionIsStale { return "Stale — last known position" }
        switch status {
        case .locationReady, .poorAccuracy, .ambiguousLocation, .calculating: return fieldPosition.status.message
        default: return "Last known position — update unavailable."
        }
    }
    public var coordinate: ProjectCoordinate? { fieldPosition?.coordinate }
    public var result: StationOffsetResult? { fieldPosition?.result }
    @Published public private(set) var permission: LocationPermission
    @Published public private(set) var preciseAccuracy: Bool
    @Published public private(set) var isRunning = false
    @Published public private(set) var alignment: Alignment?
    public var projectionMilliseconds: Double? { fieldPosition?.projectionMilliseconds }
    public private(set) var project: Project?
    public let policy: LocationQualityPolicy
    private let service: any LocationProviding
    private let factory: TransformerFactory
    private var transformer: (any ProjectCoordinateTransformer)?
    private var revision = 0
    private var selectionRevision = 0
    private var isValidatingCRS = false
    private var startedAt: Date?
    private var injectionMode = false

    public init(service: any LocationProviding, policy: LocationQualityPolicy = LocationQualityPolicy(),
                factory: @escaping TransformerFactory = { resolution, unit in
                    try PROJProjectCoordinateTransformer(resolution: resolution, outputUnit: .linear(unit))
                }) {
        self.service = service; self.policy = policy; self.factory = factory
        permission = service.permission; preciseAccuracy = service.preciseAccuracy
        service.onEvent = { [weak self] event in
            Task { [weak self] in await self?.handle(event) }
        }
    }
    public func load(project: Project) {
        stop()
        selectionRevision += 1; isValidatingCRS = false
        self.project = project; alignment = nil; confirmedCRS = nil; transformer = nil
        if case .identified = project.crsResolution { status = .crsConfirmationRequired }
        else { status = .crsRequired }
    }
    public func selectAlignment(_ alignment: Alignment, now: Date = Date()) async {
        self.alignment = alignment
        invalidate()
        await calculate(now: now)
    }
    /// Confirm the original LandXML identity without interpreting its name/description.
    public func confirmImportedCRS(now: Date = Date()) async {
        guard let project, case .identified(let crs) = project.crsResolution else { status = .crsRequired; return }
        await select(crs: crs, provenance: .landXML, now: now)
    }
    public func selectEPSG(_ text: String, now: Date = Date()) async {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.uppercased().hasPrefix("EPSG:") { value = String(value.dropFirst(5)) }
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let code = Int(value), let crs = try? CoordinateReferenceSystem(epsgCode: code) else {
            selectionRevision += 1; isValidatingCRS = false
            invalidate(); transformer = nil; confirmedCRS = nil
            status = .crsUnavailable("Enter a positive numeric EPSG code, such as 6507.")
            return
        }
        await select(crs: crs, provenance: .manual, now: now)
    }
    /// Explicit picker confirmation; catalog recommendations cannot call this themselves.
    public func confirmCatalogCRS(code: Int, now: Date = Date()) async {
        guard let crs = try? CoordinateReferenceSystem(epsgCode: code) else { return }
        await select(crs: crs, provenance: .catalog, now: now)
    }
    private func select(crs: CoordinateReferenceSystem, provenance: CRSSelectionProvenance, now: Date) async {
        guard let project else { status = .crsRequired; return }
        selectionRevision += 1; isValidatingCRS = true
        invalidate(); transformer = nil; confirmedCRS = nil; status = .calculating
        let generation = selectionRevision
        let validationStart = Date()
        let factory = factory
        do {
            let candidate = try await Task.detached {
                try factory(.identified(crs), project.unit)
            }.value
            guard generation == selectionRevision else { return }
            guard project.unit.metersPerUnit != nil, candidate.definition.outputUnit == .linear(project.unit) else {
                throw CoordinateTransformationError.incompatibleUnits
            }
            transformer = candidate
            confirmedCRS = ConfirmedProjectCRS(definition: candidate.definition, provenance: provenance)
            isValidatingCRS = false
            invalidate()
            await calculate(now: now.addingTimeInterval(Date().timeIntervalSince(validationStart)))
        } catch {
            guard generation == selectionRevision else { return }
            isValidatingCRS = false
            status = .crsUnavailable(error.localizedDescription)
        }
    }
    public func start(now: Date = Date()) {
        guard transformer != nil, alignment != nil else { return }
        invalidate(); sample = nil; injectionMode = false; startedAt = now; isRunning = true
        permission = service.permission; preciseAccuracy = service.preciseAccuracy
        switch permission {
        case .notDetermined: status = .waitingForPermission; service.requestPermission(); service.start()
        case .authorized: status = .waitingForLocation; service.start()
        case .denied: isRunning = false; status = .permissionDenied
        case .restricted: isRunning = false; status = .permissionRestricted
        }
    }
    public func stop() {
        service.stop(); isRunning = false; injectionMode = false; startedAt = nil
        sample = nil; invalidate()
        if transformer != nil { status = .stopped }
    }
    public func handle(_ event: LocationEvent, now: Date = Date()) async {
        switch event {
        case .permission(let state, let precise):
            permission = state; preciseAccuracy = precise
            guard isRunning, !injectionMode else { return }
            invalidate(clearDisplayedPosition: state != .authorized)
            if state != .authorized { sample = nil }
            switch state {
            case .notDetermined: status = .waitingForPermission
            case .denied: service.stop(); status = .permissionDenied
            case .restricted: service.stop(); status = .permissionRestricted
            case .authorized: service.start(); await calculate(now: now)
            }
        case .sample(let incoming):
            guard isRunning, !injectionMode, permission == .authorized else { return }
            // Do not let an older callback replace a more recent fix.
            if let sample, policy.quality(of: sample, now: now) != .invalidTimestamp,
               incoming.timestamp < sample.timestamp { return }
            sample = incoming; invalidate(clearDisplayedPosition: false); await calculate(now: now)
        case .failure(let detail):
            guard isRunning, !injectionMode else { return }
            invalidate(clearDisplayedPosition: false); updateDisplayedFreshness(now: now)
            status = .locationFailure(detail)
        }
    }
    #if DEBUG
    /// The sole UI injection entry point. It uses the same calculate() pipeline,
    /// with permission bypass only for explicitly labeled DEBUG synthetic input.
    public func inject(_ sample: LocationSample, now: Date = Date()) async {
        let continuingInjection = isRunning && injectionMode
        service.stop(); invalidate(clearDisplayedPosition: !continuingInjection)
        isRunning = true; injectionMode = true
        if !continuingInjection { startedAt = now }
        self.sample = LocationSample(latitude: sample.latitude, longitude: sample.longitude,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters, timestamp: sample.timestamp,
            source: .developerInjection, speedMetersPerSecond: sample.speedMetersPerSecond, courseDegrees: sample.courseDegrees)
        await calculate(now: now)
    }
    #endif
    /// Display-only freshness check. Stale fixes cannot produce new calculations,
    /// but the last completed position remains visible and explicitly last-known.
    public func refresh(now: Date = Date()) {
        guard isRunning else { return }
        updateDisplayedFreshness(now: now)
        if let sample, let blocked = blockedStatus(sample, now: now), status != blocked || isCalculating {
            invalidate(clearDisplayedPosition: false); status = blocked
        } else if displayedPositionIsStale, status == .locationReady || status == .poorAccuracy || status == .ambiguousLocation {
            status = .staleLocation
        }
    }
    private func updateDisplayedFreshness(now: Date) {
        guard let fieldPosition else { return }
        if !displayedPositionIsStale, policy.quality(of: fieldPosition.sample, now: now) == .stale {
            displayedPositionIsStale = true
        }
    }
    public func accuracyInProjectUnits() -> Double? {
        if let fieldPosition { return fieldPosition.accuracyInProjectUnits }
        guard let sample, sample.horizontalAccuracyMeters.isFinite, sample.horizontalAccuracyMeters >= 0,
              let factor = project?.unit.metersPerUnit else { return nil }
        return sample.horizontalAccuracyMeters / factor
    }
    private func invalidate(clearDisplayedPosition: Bool = true) {
        revision += 1; isCalculating = false
        if clearDisplayedPosition { fieldPosition = nil; displayedPositionIsStale = false }
    }
    private func blockedStatus(_ sample: LocationSample, now: Date) -> FieldPositionStatus? {
        if let startedAt, sample.timestamp < startedAt { return .staleLocation }
        switch policy.quality(of: sample, now: now) {
        case .stale: return .staleLocation
        case .invalidAccuracy: return .invalidAccuracy
        case .invalidCoordinate: return .invalidCoordinate
        case .invalidTimestamp: return .invalidTimestamp
        case .usable, .poorAccuracy: return nil
        }
    }
    private func calculate(now: Date) async {
        guard let transformer else {
            if isValidatingCRS { status = .calculating; return }
            // Preserve specific CRS validation error until a valid explicit selection.
            if case .crsUnavailable = status { return }
            if let project, case .identified = project.crsResolution { status = .crsConfirmationRequired }
            else { status = .crsRequired }
            return
        }
        guard isRunning else { status = .stopped; return }
        guard injectionMode || permission == .authorized else {
            status = permission == .restricted ? .permissionRestricted : permission == .denied ? .permissionDenied : .waitingForPermission
            return
        }
        guard let alignment else { status = .waitingForLocation; return }
        guard let sample else { status = .waitingForLocation; return }
        updateDisplayedFreshness(now: now)
        if let blocked = blockedStatus(sample, now: now) { status = blocked; return }
        let generation = revision
        isCalculating = true
        if fieldPosition == nil { status = .calculating }
        defer { if generation == revision { isCalculating = false } }
        do {
            let geographic = try GeographicCoordinate(latitude: sample.latitude, longitude: sample.longitude)
            let wallStart = Date()
            let values = try await Task.detached { () throws -> (ProjectCoordinate, StationOffsetResult, Double) in
                let start = Date()
                let point: ProjectCoordinate
                do { point = try transformer.projectCoordinate(from: geographic) }
                catch { throw PipelineFailure.transformation(error.localizedDescription) }
                let cost = Date().timeIntervalSince(start) * 1000
                guard point.isFinite else { throw PipelineFailure.transformation("Non-finite project coordinates.") }
                do {
                    let result = try AlignmentEngine(alignment: alignment).stationOffset(point: point)
                    return (point, result, cost)
                }
                catch { throw PipelineFailure.stationing(error.localizedDescription) }
            }.value
            guard generation == revision else { return }
            // Include time spent computing so a delayed result cannot revive an old fix.
            let completedAt = now.addingTimeInterval(Date().timeIntervalSince(wallStart))
            updateDisplayedFreshness(now: completedAt)
            if let blocked = blockedStatus(sample, now: completedAt) { status = blocked; return }
            guard let confirmedCRS, let project else { return }
            let completedStatus: FieldPositionStatus
            if values.1.nearestLocationIsAmbiguous { completedStatus = .ambiguousLocation }
            else if policy.quality(of: sample, now: completedAt) == .poorAccuracy || (!preciseAccuracy && !injectionMode) { completedStatus = .poorAccuracy }
            else { completedStatus = .locationReady }
            displayedPositionIsStale = false
            fieldPosition = FieldPositionSnapshot(result: values.1, coordinate: values.0, sample: sample,
                alignmentID: alignment.id, alignmentName: alignment.name, crs: confirmedCRS, unit: project.unit,
                status: completedStatus, preciseAccuracy: preciseAccuracy, projectionMilliseconds: values.2)
            status = completedStatus
        } catch {
            guard generation == revision else { return }
            // Failed/invalid updates never masquerade as a new successful fix.
            // Keep the previous snapshot labeled last-known until recovery/Stop.
            updateDisplayedFreshness(now: now)
            if case PipelineFailure.stationing(let detail) = error { status = .stationingFailure(detail) }
            else { status = .transformationFailure(error.localizedDescription) }
        }
    }
}
private enum PipelineFailure: LocalizedError {
    case transformation(String), stationing(String)
    var errorDescription: String? {
        switch self { case .transformation(let message), .stationing(let message): message }
    }
}
