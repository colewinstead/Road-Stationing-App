import Foundation
import CoreLocation

/// Created on the main runloop; delegate callbacks share that actor. No background mode.
@MainActor
public final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var running = false
    public var onEvent: (@MainActor (LocationEvent) -> Void)?
    public var permission: LocationPermission { Self.permission(manager.authorizationStatus) }
    public var preciseAccuracy: Bool { manager.accuracyAuthorization == .fullAccuracy }
    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self
    }
    public func requestPermission() { manager.requestWhenInUseAuthorization() }
    public func start() {
        running = true
        if permission == .authorized { manager.startUpdatingLocation() }
    }
    public func stop() { running = false; manager.stopUpdatingLocation() }
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // CLLocationManager is initialized on the main actor/runloop, as required by Apple.
        MainActor.assumeIsolated {
            if permission == .authorized, running { self.manager.startUpdatingLocation() }
            if permission != .authorized { self.manager.stopUpdatingLocation() }
            onEvent?(.permission(permission, precise: preciseAccuracy))
        }
    }
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let incoming = locations.max(by: { $0.timestamp < $1.timestamp }).map(Self.sample)
        MainActor.assumeIsolated {
            guard running, permission == .authorized, let incoming else { return }
            onEvent?(.sample(incoming))
        }
    }
    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let detail = error.localizedDescription
        MainActor.assumeIsolated {
            guard running else { return }
            // Transient failures remain visible; later updates can recover normally.
            onEvent?(.failure(detail))
        }
    }
    public nonisolated static func permission(_ authorization: CLAuthorizationStatus) -> LocationPermission {
        switch authorization {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .restricted
        }
    }
    public nonisolated static func sample(_ location: CLLocation) -> LocationSample {
        LocationSample(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                       horizontalAccuracyMeters: location.horizontalAccuracy, timestamp: location.timestamp,
                       source: location.sourceInformation?.isSimulatedBySoftware == true ? .systemSimulation : .device,
                       speedMetersPerSecond: location.speed, courseDegrees: location.course)
    }
}
