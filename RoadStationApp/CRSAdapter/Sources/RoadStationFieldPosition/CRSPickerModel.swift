import Foundation
import Combine
import RoadStationCore
import RoadStationCRSCatalog

public enum RecommendationLocationStatus: Equatable, Sendable {
    case needsPermission, waitingForPermission, finding, ready, denied, restricted, failed(String)
    public var message: String {
        switch self {
        case .needsPermission: "Uses your location once to find nearby State Plane coordinate systems."
        case .waitingForPermission: "Waiting for When In Use location permission…"
        case .finding: "Finding nearby coordinate systems…"
        case .ready: "Based on a one-time location. Recommendations stay available while this picker is open."
        case .denied: "Nearby recommendations are unavailable because location access is denied. Enable access in Settings, or browse and search."
        case .restricted: "Nearby recommendations are unavailable because location access is restricted. Browse, search, or enter EPSG manually."
        case .failed(let detail): "Recommendation location unavailable: \(detail)"
        }
    }
    public var isAcquiring: Bool { self == .finding || self == .waitingForPermission }
}
/// Validated at acquisition, never fed into stationing. Retain the captured point
/// for this sheet's recommendations without repeatedly applying live-fix expiry.
public struct RecommendationLocationSnapshot: Equatable, Sendable {
    public let sample: LocationSample
    public let point: GeographicCoordinate
    public let capturedAt: Date
    public let isApproximate: Bool
}

/// Browsing and previewing a candidate never writes the project's confirmation.
@MainActor
public final class CRSPickerModel: ObservableObject {
    @Published public private(set) var catalog: CRSCatalog?
    @Published public private(set) var error: String?
    @Published public private(set) var pending: CRSCatalogEntry?
    @Published public private(set) var searchResults: [CRSCatalogEntry] = []
    @Published public private(set) var recommendationLocation: RecommendationLocationSnapshot?
    @Published public private(set) var recommendationStatus: RecommendationLocationStatus = .needsPermission
    private let locationService: (any RecommendationLocationProviding)?
    private let recommendationPolicy: LocationQualityPolicy
    private var recommendationOpen = false
    private var searchRevision = 0
    public init(locationService: (any RecommendationLocationProviding)? = nil, policy: LocationQualityPolicy = LocationQualityPolicy()) {
        self.locationService = locationService; recommendationPolicy = policy
        locationService?.onEvent = { [weak self] event in self?.handleRecommendationEvent(event) }
    }
    public func openRecommendationLocation() {
        guard !recommendationOpen else { return }
        recommendationOpen = true
        guard let locationService else { return }
        switch locationService.permission {
        case .authorized: requestRecommendationFix()
        case .notDetermined: recommendationStatus = .needsPermission
        case .denied: recommendationStatus = .denied
        case .restricted: recommendationStatus = .restricted
        }
    }
    public func closeRecommendationLocation() {
        recommendationOpen = false
        locationService?.cancelRequest()
    }
    /// The sole permission action. No automatic prompt on opening the picker.
    public func useMyLocation() {
        guard recommendationOpen, !recommendationStatus.isAcquiring, let locationService else { return }
        switch locationService.permission {
        case .notDetermined:
            recommendationStatus = .waitingForPermission
            locationService.requestPermission()
        case .authorized: requestRecommendationFix()
        case .denied: recommendationStatus = .denied
        case .restricted: recommendationStatus = .restricted
        }
    }
    private func requestRecommendationFix() {
        guard let locationService else { return }
        recommendationStatus = .finding
        // Retain a previous list while a user-requested refresh is in flight.
        locationService.requestLocation()
    }
    func handleRecommendationEvent(_ event: LocationEvent, now: Date = Date()) {
        guard recommendationOpen, let locationService else { return }
        switch event {
        case .permission(let permission, _):
            switch permission {
            case .authorized:
                if recommendationStatus == .waitingForPermission || recommendationStatus == .needsPermission ||
                   recommendationStatus == .denied || recommendationStatus == .restricted { requestRecommendationFix() }
            case .denied, .restricted:
                locationService.cancelRequest(); recommendationLocation = nil
                recommendationStatus = permission == .denied ? .denied : .restricted
            case .notDetermined: break
            }
        case .sample(let sample):
            guard recommendationStatus == .finding, locationService.permission == .authorized else { return }
            acceptRecommendation(sample, precise: locationService.preciseAccuracy, now: now)
        case .failure(let detail):
            guard recommendationStatus == .finding else { return }
            recommendationStatus = .failed(detail)
        }
    }
    private func acceptRecommendation(_ sample: LocationSample, precise: Bool, now: Date) {
        let quality = recommendationPolicy.quality(of: sample, now: now)
        guard quality == .usable || quality == .poorAccuracy,
              let point = try? GeographicCoordinate(latitude: sample.latitude, longitude: sample.longitude) else {
            recommendationStatus = .failed("The fix is invalid or too old. Try again, browse, or search.")
            return
        }
        recommendationLocation = RecommendationLocationSnapshot(sample: sample, point: point, capturedAt: now,
            isApproximate: quality == .poorAccuracy || !precise)
        recommendationStatus = .ready
    }
    public func capturedRecommendations(unit: ProjectUnit) -> [CRSRecommendation] {
        catalog?.recommendations(at: recommendationLocation?.point, projectUnit: unit) ?? []
    }
    public func capturedAreaWarning(entry: CRSCatalogEntry?) -> String? {
        guard let entry, !entry.areas.isEmpty, let location = recommendationLocation,
            !entry.contains(location.point) else { return nil }
        return "The one-time recommendation location appears outside this CRS's published area of use."
    }
    #if DEBUG
    public func injectRecommendation(_ sample: LocationSample, now: Date = Date()) {
        guard recommendationOpen else { return }
        locationService?.cancelRequest()
        let injected = LocationSample(latitude: sample.latitude, longitude: sample.longitude,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters, timestamp: sample.timestamp, source: .developerInjection)
        acceptRecommendation(injected, precise: true, now: now)
    }
    #endif
    public func load() async {
        do { catalog = try await CRSCatalogStore.shared.catalog() }
        catch { self.error = "CRS catalog unavailable. Manual EPSG entry remains available." }
    }
    public func preview(_ entry: CRSCatalogEntry) { pending = entry }
    public func cancelPreview() { pending = nil }
    public func confirm(in session: FieldPositionSession) async {
        guard let pending else { return }
        await session.confirmCatalogCRS(code: pending.code)
        self.pending = nil
    }
    public func search(_ query: String) async {
        guard !Task.isCancelled else { return }
        searchRevision += 1
        let revision = searchRevision
        guard let catalog else { return }
        let results = await Task.detached { catalog.search(query) }.value
        guard revision == searchRevision, !Task.isCancelled else { return }
        searchResults = results
    }
    public static func recommendationPoint(sample: LocationSample?, permission: LocationPermission,
        policy: LocationQualityPolicy, now: Date) -> GeographicCoordinate? {
        guard let sample, permission == .authorized || sample.source == .developerInjection else { return nil }
        let quality = policy.quality(of: sample, now: now)
        guard quality == .usable || quality == .poorAccuracy else { return nil }
        return try? GeographicCoordinate(latitude: sample.latitude, longitude: sample.longitude)
    }
    public func recommendations(sample: LocationSample?, permission: LocationPermission,
        policy: LocationQualityPolicy, unit: ProjectUnit, now: Date) -> [CRSRecommendation] {
        catalog?.recommendations(at: Self.recommendationPoint(sample: sample, permission: permission, policy: policy, now: now), projectUnit: unit) ?? []
    }
    public static func outsideAreaWarning(entry: CRSCatalogEntry?, sample: LocationSample?,
        permission: LocationPermission, policy: LocationQualityPolicy, now: Date) -> String? {
        guard let entry, !entry.areas.isEmpty,
            let point = recommendationPoint(sample: sample, permission: permission, policy: policy, now: now),
            !entry.contains(point) else { return nil }
        return "Current location appears outside this CRS's published area of use."
    }
}
