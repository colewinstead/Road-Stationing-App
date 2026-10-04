import Foundation
import RoadStationCore

public enum LocationPermission: Equatable, Sendable {
    case notDetermined, denied, restricted, authorized
}
public enum LocationSource: String, Sendable {
    case device = "Device location"
    case systemSimulation = "Simulated by location system"
    case developerInjection = "DEBUG injected location"
}
/// CLLocation-like data at the Apple boundary, suitable for deterministic injection.
public struct LocationSample: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracyMeters: Double
    public let timestamp: Date
    public let source: LocationSource
    public let speedMetersPerSecond: Double?
    public let courseDegrees: Double?
    public init(latitude: Double, longitude: Double, horizontalAccuracyMeters: Double,
                timestamp: Date, source: LocationSource = .device,
                speedMetersPerSecond: Double? = nil, courseDegrees: Double? = nil) {
        self.latitude = latitude; self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters; self.timestamp = timestamp; self.source = source
        self.speedMetersPerSecond = speedMetersPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.courseDegrees = courseDegrees.flatMap { $0.isFinite && (0..<360).contains($0) ? $0 : nil }
    }
}
public enum LocationQuality: Equatable, Sendable {
    case usable, poorAccuracy, stale, invalidAccuracy, invalidCoordinate, invalidTimestamp
}
public struct LocationQualityPolicy: Sendable {
    public let maximumAgeSeconds: Double
    public let warningAccuracyMeters: Double
    public let maximumFutureSkewSeconds: Double
    public init(maximumAgeSeconds: Double = 5, warningAccuracyMeters: Double = 10,
                maximumFutureSkewSeconds: Double = 2) {
        precondition(maximumAgeSeconds.isFinite && maximumAgeSeconds > 0)
        precondition(warningAccuracyMeters.isFinite && warningAccuracyMeters > 0)
        precondition(maximumFutureSkewSeconds.isFinite && maximumFutureSkewSeconds >= 0)
        self.maximumAgeSeconds = maximumAgeSeconds; self.warningAccuracyMeters = warningAccuracyMeters
        self.maximumFutureSkewSeconds = maximumFutureSkewSeconds
    }
    public func quality(of sample: LocationSample, now: Date) -> LocationQuality {
        guard sample.horizontalAccuracyMeters.isFinite, sample.horizontalAccuracyMeters >= 0 else { return .invalidAccuracy }
        guard (try? GeographicCoordinate(latitude: sample.latitude, longitude: sample.longitude)) != nil else { return .invalidCoordinate }
        let age = now.timeIntervalSince(sample.timestamp)
        guard age.isFinite, age >= -maximumFutureSkewSeconds else { return .invalidTimestamp }
        guard age <= maximumAgeSeconds else { return .stale }
        return sample.horizontalAccuracyMeters > warningAccuracyMeters ? .poorAccuracy : .usable
    }
}
public enum LocationEvent: Sendable {
    case permission(LocationPermission, precise: Bool)
    case sample(LocationSample)
    case failure(String)
}
@MainActor
public protocol LocationProviding: AnyObject {
    var permission: LocationPermission { get }
    var preciseAccuracy: Bool { get }
    var onEvent: (@MainActor (LocationEvent) -> Void)? { get set }
    func requestPermission()
    func start()
    func stop()
}

public enum CRSSelectionProvenance: String, Sendable {
    case landXML = "Imported from LandXML, confirmed by user"
    case manual = "Manually selected by user"
    case catalog = "Selected from CRS catalog, confirmed by user"
}
public struct ConfirmedProjectCRS: Equatable, Sendable {
    public let definition: ResolvedCRS
    public let provenance: CRSSelectionProvenance
}
/// A completed position and its matching display context. Never combine the
/// previous station with the accuracy/timestamp/context of a pending fix.
public struct FieldPositionSnapshot: Equatable, Sendable {
    public let result: StationOffsetResult
    public let coordinate: ProjectCoordinate
    public let sample: LocationSample
    public let alignmentID: UUID
    public let alignmentName: String
    public let crs: ConfirmedProjectCRS
    public let unit: ProjectUnit
    public let status: FieldPositionStatus
    public let preciseAccuracy: Bool
    public let projectionMilliseconds: Double
    public var accuracyInProjectUnits: Double { sample.horizontalAccuracyMeters / unit.metersPerUnit! }
    public func age(at date: Date) -> Double { max(0, date.timeIntervalSince(sample.timestamp)) }

    // Core's numerical result deliberately remains unchanged. Compare its
    // immutable values here rather than adding UI conformances to the core.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate == rhs.coordinate && lhs.sample == rhs.sample &&
        lhs.alignmentID == rhs.alignmentID && lhs.alignmentName == rhs.alignmentName &&
        lhs.crs == rhs.crs && lhs.unit == rhs.unit && lhs.status == rhs.status &&
        lhs.preciseAccuracy == rhs.preciseAccuracy && lhs.projectionMilliseconds == rhs.projectionMilliseconds &&
        lhs.result.geometricDistance == rhs.result.geometricDistance &&
        lhs.result.displayedStation == rhs.result.displayedStation && lhs.result.signedOffset == rhs.result.signedOffset &&
        lhs.result.side == rhs.result.side && lhs.result.nearestPoint == rhs.result.nearestPoint &&
        lhs.result.nearestSegmentIndex == rhs.result.nearestSegmentIndex &&
        lhs.result.distanceFromQueryPointToAlignment == rhs.result.distanceFromQueryPointToAlignment &&
        lhs.result.tangent.x == rhs.result.tangent.x && lhs.result.tangent.y == rhs.result.tangent.y &&
        lhs.result.longitudinalResidual == rhs.result.longitudinalResidual &&
        lhs.result.nearestLocationIsAmbiguous == rhs.result.nearestLocationIsAmbiguous &&
        lhs.result.segmentType == rhs.result.segmentType
    }
}
public enum FieldPositionStatus: Equatable, Sendable {
    case crsRequired, crsConfirmationRequired, crsUnavailable(String)
    case waitingForPermission, permissionDenied, permissionRestricted
    case stopped, waitingForLocation, staleLocation, invalidAccuracy, invalidCoordinate, invalidTimestamp
    case locationFailure(String), transformationFailure(String), stationingFailure(String)
    case calculating, locationReady, poorAccuracy, ambiguousLocation
    public var message: String {
        switch self {
        case .crsRequired: "CRS required — choose and confirm a coordinate system."
        case .crsConfirmationRequired: "Confirm the imported EPSG before live positioning."
        case .crsUnavailable(let detail): "CRS unavailable: \(detail)"
        case .waitingForPermission: "Waiting for When In Use location permission."
        case .permissionDenied: "Location permission denied. Enable it in iPhone Settings to use device location."
        case .permissionRestricted: "Location permission restricted by device policy."
        case .stopped: "Location stopped. Start Location to receive a current fix."
        case .waitingForLocation: "Waiting for a current location."
        case .staleLocation: "Stale location — stationing withheld until a current fix arrives."
        case .invalidAccuracy: "Invalid GPS accuracy — stationing withheld."
        case .invalidCoordinate: "Invalid geographic coordinate — stationing withheld."
        case .invalidTimestamp: "Invalid location timestamp — stationing withheld."
        case .locationFailure(let detail): "Location unavailable: \(detail)"
        case .transformationFailure(let detail): "Transformation failed: \(detail)"
        case .stationingFailure(let detail): "Stationing failed: \(detail)"
        case .calculating: "Calculating field position…"
        case .locationReady: "Location ready."
        case .poorAccuracy: "Poor GPS accuracy — approximate station/offset shown with warning."
        case .ambiguousLocation: "AMBIGUOUS nearest location — representative result only."
        }
    }
}
