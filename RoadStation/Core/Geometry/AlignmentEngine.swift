import Foundation

public struct AlignmentEngine: Sendable {
    public let alignment: Alignment
    public init(alignment: Alignment) { self.alignment = alignment }
    public func stationOffset(point: ProjectCoordinate) throws -> StationOffsetResult {
        guard point.isFinite else { throw GeometryError.invalidGeometry("Query point must be finite.") }
        var candidates: [(Int, SegmentProjection)] = []
        let bounds: [(index: Int, lowerBound: Double)] = alignment.segments.indices.map { index in
            (index: index, lowerBound: alignment.segments[index].bounds.distance(to: point))
        }
        let ordered = bounds.sorted { a, b in
            if a.lowerBound == b.lowerBound { return a.index < b.index }
            return a.lowerBound < b.lowerBound
        }
        var bestDistance = Double.infinity
        for (i, lowerBound) in ordered {
            if lowerBound > bestDistance + GeometryTolerances.standard.tieDistance { break }
            let projection = try alignment.segments[i].geometry.closestPoint(to: point)
            candidates.append((i, projection)); bestDistance = min(bestDistance, projection.queryDistance)
        }
        // Ties have deterministic segment order, with ambiguity retained.
        let best = candidates.min {
            $0.1.queryDistance == $1.1.queryDistance ? $0.0 < $1.0 : $0.1.queryDistance < $1.1.queryDistance
        }!
        let segment = alignment.segments[best.0]; let projection = best.1
        let d = segment.geometricStartDistance + projection.distanceAlong
        let offset = OffsetEngine.signedOffset(tangent: projection.tangent, from: projection.point, to: point)
        let ambiguous = projection.ambiguous || candidates.contains { candidate in
            let otherD = alignment.segments[candidate.0].geometricStartDistance + candidate.1.distanceAlong
            let otherTangent = candidate.1.tangent
            return abs(candidate.1.queryDistance - projection.queryDistance) <= GeometryTolerances.standard.tieDistance &&
                (abs(otherD - d) > GeometryTolerances.standard.station ||
                 abs(otherTangent.cross(projection.tangent)) > GeometryTolerances.standard.tangentAmbiguity ||
                 otherTangent.dot(projection.tangent) < 0)
        }
        return StationOffsetResult(geometricDistance: d, displayedStation: try StationingEngine(alignment: alignment).station(at: d),
            signedOffset: offset, side: abs(offset) <= GeometryTolerances.standard.coordinate ? .onAlignment : (offset > 0 ? .left : .right),
            nearestPoint: projection.point, nearestSegmentIndex: best.0, distanceFromQueryPointToAlignment: projection.queryDistance,
            tangent: projection.tangent, longitudinalResidual: GeometryUtilities.displacement(from: projection.point, to: point).dot(projection.tangent),
            nearestLocationIsAmbiguous: ambiguous, segmentType: segment.geometry.typeName)
    }
    public func point(at geometricDistance: Double) throws -> (point: ProjectCoordinate, tangent: Vector2, segmentIndex: Int) {
        let d = try GeometryUtilities.checkedDistance(geometricDistance, length: alignment.totalGeometricLength)
        // At shared boundaries choose the incoming segment, matching forward ties.
        let index = alignment.segments.firstIndex { d <= $0.geometricEndDistance } ?? alignment.segments.count - 1
        let segment = alignment.segments[index]; let local = d - segment.geometricStartDistance
        return (try segment.geometry.point(at: local), segment.geometry.tangent(at: local), index)
    }
    public func coordinate(station: Double, offset: Double, branchIndex: Int? = nil) throws -> CoordinateResult {
        guard offset.isFinite else { throw GeometryError.invalidGeometry("Offset must be finite.") }
        let location = try StationingEngine(alignment: alignment).location(station: station, branchIndex: branchIndex)
        let p = try point(at: location.geometricDistance)
        return CoordinateResult(coordinate: OffsetEngine.coordinate(centerline: p.point, tangent: p.tangent, offset: offset),
            geometricDistance: location.geometricDistance, nearestSegmentIndex: p.segmentIndex, stationLocation: location)
    }
}
