import Foundation
import RoadStationCore
import Projections
import proj
import ProjectionResources

/// Immutable settings; each call owns a fresh PROJ context/operation. No C handles
/// cross threads, no global PROJ configuration is changed, and no network is used.
public struct PROJProjectCoordinateTransformer: ProjectCoordinateTransformer {
    public let definition: ResolvedCRS

    public init(resolution: CRSResolution, outputUnit: CoordinateUnit) throws {
        guard case .identified(let crs) = resolution else {
            if case .unresolved(let reason) = resolution {
                throw CoordinateTransformationError.unresolvedCRS(reason)
            }
            throw CoordinateTransformationError.unsupportedCRS("Unidentified CRS")
        }
        definition = try Self.withContext { context in
            let nativeUnit = try Self.inspect(crs: crs, context: context)
            _ = try Self.scale(nativeUnit: nativeUnit, outputUnit: outputUnit)
            let operation = try Self.operation(crs: crs, context: context)
            proj_destroy(operation)
            return ResolvedCRS(crs: crs, nativeUnit: nativeUnit, outputUnit: outputUnit)
        }
    }

    public static func readiness(resolution: CRSResolution, outputUnit: CoordinateUnit) -> CRSReadiness {
        if case .unresolved(let reason) = resolution { return .unresolved(reason) }
        do { return .ready(try Self(resolution: resolution, outputUnit: outputUnit).definition) }
        catch let error as CoordinateTransformationError { return .unavailable(error) }
        catch { return .unavailable(.backendUnavailable(error.localizedDescription)) }
    }

    public func projectCoordinate(from coordinate: GeographicCoordinate) throws -> ProjectCoordinate {
        let result = try transform(x: coordinate.longitude, y: coordinate.latitude, direction: PJ_FWD)
        let factor = try Self.scale(nativeUnit: definition.nativeUnit, outputUnit: definition.outputUnit)
        let output = ProjectCoordinate(x: result.x * factor, y: result.y * factor)
        guard output.isFinite else { throw CoordinateTransformationError.nonFiniteCoordinate }
        return output
    }

    public func geographicCoordinate(from coordinate: ProjectCoordinate) throws -> GeographicCoordinate {
        guard coordinate.isFinite else { throw CoordinateTransformationError.nonFiniteCoordinate }
        guard coordinate.z == nil else { throw CoordinateTransformationError.unexpectedHeight }
        let factor = try Self.scale(nativeUnit: definition.nativeUnit, outputUnit: definition.outputUnit)
        let result = try transform(x: coordinate.x / factor, y: coordinate.y / factor, direction: PJ_INV)
        return try GeographicCoordinate(latitude: result.y, longitude: result.x)
    }

    private func transform(x: Double, y: Double, direction: PJ_DIRECTION) throws -> ProjectCoordinate {
        guard x.isFinite, y.isFinite else { throw CoordinateTransformationError.nonFiniteCoordinate }
        return try Self.withContext { context in
            let operation = try Self.operation(crs: definition.crs, context: context)
            defer { proj_destroy(operation) }
            proj_errno_reset(operation)
            let result = proj_trans(operation, direction, proj_coord(x, y, 0, 0))
            guard proj_errno(operation) == 0 else {
                throw CoordinateTransformationError.transformationFailed(Self.errorDetail(context))
            }
            guard result.xy.x.isFinite, result.xy.y.isFinite else {
                throw CoordinateTransformationError.nonFiniteCoordinate
            }
            // This is horizontal only. Never attach the temporary PROJ z=0 to a project point.
            return ProjectCoordinate(x: result.xy.x, y: result.xy.y)
        }
    }

    private static func withContext<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let database = RSProjectionDatabasePath(), FileManager.default.fileExists(atPath: database),
              let context = proj_context_create() else {
            throw CoordinateTransformationError.backendUnavailable("NGA proj.db/context is missing.")
        }
        defer { proj_context_destroy(context) }
        proj_log_level(context, PJ_LOG_NONE)
        proj_context_set_enable_network(context, 0)
        guard proj_context_set_database_path(context, database, nil, nil) != 0 else {
            throw CoordinateTransformationError.backendUnavailable(errorDetail(context))
        }
        return try body(context)
    }

    private static func inspect(crs: CoordinateReferenceSystem, context: OpaquePointer) throws -> CoordinateUnit {
        guard let native = proj_create(context, crs.identifier) else {
            throw CoordinateTransformationError.unsupportedCRS(crs.identifier)
        }
        defer { proj_destroy(native) }
        let type = proj_get_type(native)
        guard type == PJ_TYPE_PROJECTED_CRS || type == PJ_TYPE_GEOGRAPHIC_2D_CRS else {
            throw CoordinateTransformationError.unsupportedCRS(crs.identifier)
        }
        guard let normalized = proj_normalize_for_visualization(context, native) else {
            throw CoordinateTransformationError.unsupportedAxes(crs.identifier)
        }
        defer { proj_destroy(normalized) }
        guard let cs = proj_crs_get_coordinate_system(context, normalized) else {
            throw CoordinateTransformationError.unsupportedAxes(crs.identifier)
        }
        defer { proj_destroy(cs) }
        guard proj_cs_get_axis_count(context, cs) == 2 else {
            throw CoordinateTransformationError.unsupportedAxes(crs.identifier)
        }
        var units: [CoordinateUnit] = []
        for index in 0..<2 {
            var direction: UnsafePointer<CChar>?
            var authority: UnsafePointer<CChar>?
            var code: UnsafePointer<CChar>?
            var factor = 0.0
            guard proj_cs_get_axis_info(context, cs, Int32(index), nil, nil, &direction,
                                        &factor, nil, &authority, &code) != 0,
                  let direction, String(cString: direction) == (index == 0 ? "east" : "north") else {
                // Unusual south/west, polar and oblique axes need a separate explicit mapping.
                throw CoordinateTransformationError.unsupportedAxes(crs.identifier)
            }
            guard let authority, let code, String(cString: authority) == "EPSG" else {
                throw CoordinateTransformationError.unsupportedUnits
            }
            let unit: CoordinateUnit
            let expectedFactor: Double
            switch String(cString: code) {
            case "9001": unit = .linear(.meter); expectedFactor = 1
            case "9002": unit = .linear(.internationalFoot); expectedFactor = 0.3048
            case "9003": unit = .linear(.usSurveyFoot); expectedFactor = 1200.0 / 3937.0
            // EPSG 9122 is degree for coordinate-system axes; 9102 is degree
            // for operation parameters. Both have the same angular definition.
            case "9102", "9122": unit = .degree; expectedFactor = .pi / 180
            default: throw CoordinateTransformationError.unsupportedUnits
            }
            guard factor.isFinite, abs(factor - expectedFactor) < 1e-14 else {
                throw CoordinateTransformationError.unsupportedUnits
            }
            units.append(unit)
        }
        guard units[0] == units[1], (type == PJ_TYPE_GEOGRAPHIC_2D_CRS) == (units[0] == .degree) else {
            throw CoordinateTransformationError.unsupportedUnits
        }
        return units[0]
    }

    private static func operation(crs: CoordinateReferenceSystem, context: OpaquePointer) throws -> OpaquePointer {
        guard let source = proj_create(context, "EPSG:4326") else {
            throw CoordinateTransformationError.backendUnavailable(errorDetail(context))
        }
        defer { proj_destroy(source) }
        guard let destination = proj_create(context, crs.identifier) else {
            throw CoordinateTransformationError.unsupportedCRS(crs.identifier)
        }
        defer { proj_destroy(destination) }
        // Reject silent approximate datum fallback; missing best-operation grids fail.
        let raw = "ALLOW_BALLPARK=NO".withCString { ballpark in
            "ONLY_BEST=YES".withCString { best in
                let options: [UnsafePointer<CChar>?] = [ballpark, best, nil]
                return options.withUnsafeBufferPointer {
                    proj_create_crs_to_crs_from_pj(context, source, destination, nil, $0.baseAddress)
                }
            }
        }
        guard let raw else { throw CoordinateTransformationError.operationUnavailable(errorDetail(context)) }
        defer { proj_destroy(raw) }
        // Explicit authority-axis -> RoadStation-axis conversion in both directions.
        guard let normalized = proj_normalize_for_visualization(context, raw) else {
            throw CoordinateTransformationError.unsupportedAxes(crs.identifier)
        }
        guard proj_pj_info(normalized).has_inverse != 0 else {
            proj_destroy(normalized)
            throw CoordinateTransformationError.operationUnavailable("Operation has no inverse.")
        }
        return normalized
    }

    private static func scale(nativeUnit: CoordinateUnit, outputUnit: CoordinateUnit) throws -> Double {
        switch (nativeUnit, outputUnit) {
        case (.degree, .degree): return 1
        case (.linear(let native), .linear(let output)):
            guard let from = native.metersPerUnit, let to = output.metersPerUnit else {
                throw CoordinateTransformationError.unsupportedUnits
            }
            return from / to
        default: throw CoordinateTransformationError.incompatibleUnits
        }
    }

    private static func errorDetail(_ context: OpaquePointer) -> String {
        let code = proj_context_errno(context)
        return proj_context_errno_string(context, code).map { String(cString: $0) } ?? "PROJ error \(code)"
    }
}
