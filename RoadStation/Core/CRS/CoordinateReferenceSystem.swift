import Foundation

/// An explicit EPSG identity; syntax validity does not imply backend support.
public struct CoordinateReferenceSystem: Equatable, Hashable, Sendable {
    public let epsgCode: Int
    public var identifier: String { "EPSG:\(epsgCode)" }

    public init(epsgCode: Int) throws {
        guard epsgCode > 0, epsgCode <= Int(Int32.max) else {
            throw CoordinateTransformationError.invalidEPSGCode(epsgCode)
        }
        self.epsgCode = epsgCode
    }

    public static let wgs84 = try! CoordinateReferenceSystem(epsgCode: 4326)
}

public enum CRSUnresolvedReason: Equatable, Sendable {
    case missingIdentification
    case invalidIdentification(String)
}

/// Import identification is separate from backend/units/operation readiness.
public enum CRSResolution: Equatable, Sendable {
    case unresolved(CRSUnresolvedReason)
    case identified(CoordinateReferenceSystem)
}

/// Degrees are explicit: geographic identity output is never a planar foot/metre.
public enum CoordinateUnit: Equatable, Sendable {
    case degree
    case linear(ProjectUnit)
}

public struct ResolvedCRS: Equatable, Sendable {
    public let crs: CoordinateReferenceSystem
    public let nativeUnit: CoordinateUnit
    public let outputUnit: CoordinateUnit
    public init(crs: CoordinateReferenceSystem, nativeUnit: CoordinateUnit, outputUnit: CoordinateUnit) {
        self.crs = crs; self.nativeUnit = nativeUnit; self.outputUnit = outputUnit
    }
}

public enum CRSReadiness: Equatable, Sendable {
    case unresolved(CRSUnresolvedReason)
    case unavailable(CoordinateTransformationError)
    /// Backend has checked the definition, axes, units and operation availability.
    /// This does not establish field/survey accuracy or validity for every point.
    case ready(ResolvedCRS)
}
