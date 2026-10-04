import Foundation
import CoreLocation

/// Deliberately has no continuous-update or Always-authorization operation.
@MainActor
public protocol RecommendationLocationProviding: AnyObject {
    var permission: LocationPermission { get }
    var preciseAccuracy: Bool { get }
    var onEvent: (@MainActor (LocationEvent) -> Void)? { get set }
    func requestPermission()
    func requestLocation()
    func cancelRequest()
}

/// Manager seam verifies the production adapter's actual calls without using GPS.
@MainActor
protocol RecommendationLocationManaging: AnyObject {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func stopUpdatingLocation()
}
extension CLLocationManager: RecommendationLocationManaging {}

/// Own manager, separate from Field Position. requestLocation automatically ends
/// after one result/error. stopUpdatingLocation cancels ONLY this manager's request
/// (the cancellation operation documented by CLLocationManager.h).
@MainActor
public final class CoreLocationRecommendationService: NSObject, RecommendationLocationProviding, CLLocationManagerDelegate {
    private let manager: any RecommendationLocationManaging
    private var pending = false
    public var onEvent: (@MainActor (LocationEvent) -> Void)?
    public var permission: LocationPermission { CoreLocationService.permission(manager.authorizationStatus) }
    public var preciseAccuracy: Bool { manager.accuracyAuthorization == .fullAccuracy }
    public convenience override init() { self.init(manager: CLLocationManager()) }
    init(manager: any RecommendationLocationManaging) {
        self.manager = manager
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.delegate = self
    }
    public func requestPermission() {
        guard permission == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }
    public func requestLocation() {
        guard permission == .authorized, !pending else { return }
        pending = true
        manager.requestLocation()
    }
    public func cancelRequest() {
        pending = false
        manager.stopUpdatingLocation()
    }
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            if permission != .authorized { cancelRequest() }
            onEvent?(.permission(permission, precise: preciseAccuracy))
        }
    }
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let incoming = locations.max(by: { $0.timestamp < $1.timestamp }).map(CoreLocationService.sample)
        MainActor.assumeIsolated {
            guard pending, permission == .authorized else { return }
            pending = false
            if let incoming { onEvent?(.sample(incoming)) }
            else { onEvent?(.failure("No location was returned. Try again or browse coordinate systems.")) }
        }
    }
    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let detail = error.localizedDescription
        MainActor.assumeIsolated {
            guard pending else { return }
            pending = false
            onEvent?(.failure(detail))
        }
    }
}
