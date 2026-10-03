import Foundation

struct LandXMLAlignmentParser {
    let options: LandXMLParserOptions
    let directionUnit: String
    private func number(_ node: XMLNode, _ attribute: String, required: Bool = true) throws -> Double? {
        guard let text = node.attributes[attribute] else {
            if required { throw LandXMLParsingError.invalidAttribute("\(node.name).\(attribute) is required.") }
            return nil
        }
        guard let value = Double(text), value.isFinite else { throw LandXMLParsingError.invalidAttribute("\(node.name).\(attribute)=\(text)") }
        return value
    }
    private func coordinate(_ node: XMLNode, _ name: String) throws -> ProjectCoordinate {
        guard node.children.filter({ $0.name == name }).count == 1 else {
            throw LandXMLParsingError.missingCoordinates("\(node.name)/\(name) must appear exactly once")
        }
        guard let child = node.child(name) else { throw LandXMLParsingError.missingCoordinates("\(node.name)/\(name)") }
        if child.attributes["pntRef"] != nil { throw LandXMLParsingError.unsupportedGeometry("Referenced coordinates (pntRef)") }
        return try LandXMLParser.coordinate(from: child.text)
    }
    private func rotation(_ node: XMLNode) throws -> Rotation {
        switch node.attributes["rot"]?.lowercased() {
        case "cw": return .clockwise
        case "ccw": return .counterclockwise
        default: throw LandXMLParsingError.invalidAttribute("\(node.name).rot must be cw or ccw.")
        }
    }
    private func heading(_ node: XMLNode, _ attribute: String) throws -> Double? {
        guard let v = try number(node, attribute, required: false) else { return nil }
        let radians: Double
        switch directionUnit {
        case "radians": radians = v
        case "decimal degrees", "decimaldegrees", "degrees": radians = v * .pi / 180
        case "grads", "gon": radians = v * .pi / 200
        default: throw LandXMLParsingError.invalidAttribute("Unsupported directionUnit \(directionUnit).")
        }
        return options.directionConvention.heading(radians)
    }
    private func curvature(_ node: XMLNode, _ attribute: String, rotation: Rotation) throws -> Double {
        guard let value = node.attributes[attribute] else { throw LandXMLParsingError.invalidAttribute("\(attribute) is required.") }
        if value.uppercased() == "INF" { return 0 }
        guard let r = Double(value), r.isFinite, r > 0 else { throw LandXMLParsingError.invalidAttribute("\(attribute) requires positive radius or INF.") }
        return rotation.sign / r
    }
    func parse(_ node: XMLNode) throws -> Alignment {
        let startStation = try number(node, "staStart", required: false) ?? 0
        guard let coordGeom = node.child("CoordGeom") else { throw LandXMLParsingError.missingAlignment }
        guard node.children.filter({ $0.name == "CoordGeom" }).count == 1 else { throw LandXMLParsingError.unsupportedGeometry("Multiple CoordGeom containers per alignment") }
        var geometries: [SegmentGeometry] = []
        var warnings: [String] = []
        for element in coordGeom.children {
            if element.name == "Feature" { continue }
            guard ["Line", "Curve", "Spiral"].contains(element.name) else {
                throw LandXMLParsingError.unsupportedGeometry(element.name)
            }
            do {
                let start = try coordinate(element, "Start"); let end = try coordinate(element, "End")
                switch element.name {
                case "Line":
                    let line = try LineSegment(start: start, end: end, tolerances: options.tolerances)
                    if let length = try number(element, "length", required: false),
                       abs(length - line.length) > options.tolerances.importConsistency {
                        throw GeometryError.invalidGeometry("Line declared length differs from horizontal endpoint distance.")
                    }
                    geometries.append(.line(line))
                case "Curve":
                    if let kind = element.attributes["crvType"], kind != "arc" { throw LandXMLParsingError.unsupportedGeometry("Curve crvType=\(kind)") }
                    let rotation = try rotation(element)
                    let radius = try number(element, "radius", required: false)
                    let length = try number(element, "length", required: false)
                    let center: ProjectCoordinate
                    if element.child("Center") != nil { center = try coordinate(element, "Center") }
                    else { center = try deriveCenter(start: start, end: end, radius: radius, rotation: rotation, declaredLength: length) }
                    geometries.append(.circularCurve(try CircularCurveSegment(start: start, end: end, center: center,
                        rotation: rotation, radius: radius, declaredLength: length, tolerances: options.tolerances)))
                case "Spiral":
                    guard element.attributes["spiType"]?.lowercased() == "clothoid" else {
                        throw LandXMLParsingError.unsupportedGeometry("Spiral spiType=\(element.attributes["spiType"] ?? "undeclared")")
                    }
                    let length = try number(element, "length")!
                    let rotation = try rotation(element)
                    let k0 = try curvature(element, "radiusStart", rotation: rotation)
                    let k1 = try curvature(element, "radiusEnd", rotation: rotation)
                    let declaredHeading = try heading(element, "dirStart")
                    let piHeading: Double?
                    var headingTolerance = options.tolerances.angle
                    if element.child("PI") != nil {
                        let pi = try coordinate(element, "PI")
                        guard start.distance(to: pi) > options.tolerances.coordinate else { throw GeometryError.invalidGeometry("Spiral PI equals Start.") }
                        piHeading = atan2(pi.y - start.y, pi.x - start.x)
                        headingTolerance = max(headingTolerance, options.tolerances.importConsistency / start.distance(to: pi))
                    } else { piHeading = nil }
                    guard let theta = piHeading ?? declaredHeading else { throw GeometryError.invalidGeometry("Clothoid needs PI or dirStart.") }
                    if let declaredHeading, let piHeading,
                       abs(atan2(sin(declaredHeading - piHeading), cos(declaredHeading - piHeading))) > headingTolerance {
                        throw GeometryError.invalidGeometry("PI and dirStart disagree; check explicit direction convention.")
                    }
                    let spiral = try SpiralSegment(start: start, length: length, startHeading: theta,
                        startCurvature: k0, endCurvature: k1, declaredEnd: end, tolerances: options.tolerances)
                    if let thetaEnd = try heading(element, "dirEnd"),
                       abs(atan2(sin(thetaEnd - spiral.heading(at: length)), cos(thetaEnd - spiral.heading(at: length)))) > options.tolerances.angle {
                        throw GeometryError.invalidGeometry("Spiral dirEnd disagrees with integrated curvature.")
                    }
                    geometries.append(.spiral(spiral))
                default: throw LandXMLParsingError.unsupportedGeometry(element.name)
                }
            } catch let error as LandXMLParsingError { throw error }
            catch { throw LandXMLParsingError.malformedGeometry(element.name, error.localizedDescription) }
        }
        var equations: [StationEquation] = []
        for e in node.children where e.name == "StaEquation" {
            if let increment = e.attributes["staIncrement"], increment.lowercased() != "increasing" {
                throw LandXMLParsingError.unsupportedGeometry("staIncrement=\(increment); decreasing station branches")
            }
            do {
                let distance = try number(e, "staInternal")! - startStation
                let ahead = try number(e, "staAhead")!
                let back = try number(e, "staBack", required: false)
                // Missing back is derived only after sorting by internal distance.
                equations.append(StationEquation(geometricDistance: distance, stationBack: back ?? .nan, stationAhead: ahead))
            } catch { throw LandXMLParsingError.invalidStationEquation(error.localizedDescription) }
        }
        equations.sort { $0.geometricDistance < $1.geometricDistance }
        var shift = startStation
        equations = equations.map { e in
            let value = StationEquation(geometricDistance: e.geometricDistance,
                stationBack: e.stationBack.isNaN ? e.geometricDistance + shift : e.stationBack, stationAhead: e.stationAhead)
            shift = e.stationAhead - e.geometricDistance
            return value
        }
        for name in ["Profile", "CrossSects", "Superelevation"] where node.child(name) != nil {
            warnings.append("\(name) is outside Phase 1 horizontal geometry scope and was not imported.")
        }
        do {
            return try Alignment(name: node.attributes["name"] ?? "Unnamed alignment", startStation: startStation,
                geometries: geometries, stationEquations: equations,
                metadata: AlignmentMetadata(description: node.attributes["desc"] ?? node.attributes["description"],
                    sourceIdentifier: node.attributes["oID"] ?? node.attributes["id"], declaredLength: try number(node, "length", required: false)),
                warnings: warnings, tolerances: options.tolerances)
        } catch let e as GeometryError {
            if case .invalidStationEquation = e { throw LandXMLParsingError.invalidStationEquation(e.localizedDescription) }
            throw LandXMLParsingError.malformedGeometry("Alignment", e.localizedDescription)
        }
    }
    private func deriveCenter(start: ProjectCoordinate, end: ProjectCoordinate, radius: Double?, rotation: Rotation,
                              declaredLength: Double?) throws -> ProjectCoordinate {
        guard let radius, radius.isFinite, radius > 0 else { throw GeometryError.invalidGeometry("Center derivation requires radius.") }
        let chord = start.distance(to: end)
        guard chord > options.tolerances.coordinate, chord <= 2 * radius + options.tolerances.importConsistency else {
            throw GeometryError.invalidGeometry("Impossible or zero chord for center derivation.")
        }
        let mid = ProjectCoordinate(x: start.x + (end.x - start.x) / 2, y: start.y + (end.y - start.y) / 2)
        let normal = Vector2(x: -(end.y - start.y) / chord, y: (end.x - start.x) / chord)
        let height = sqrt(max(0, radius * radius - chord * chord / 4))
        if height <= options.tolerances.coordinate { return mid }
        // Without length both minor and major arcs can fit: require disambiguation.
        guard let declaredLength else { throw GeometryError.invalidGeometry("Centerless curve needs length to disambiguate minor/major arc.") }
        let centers = [GeometryUtilities.translated(mid, by: normal, scale: height), GeometryUtilities.translated(mid, by: normal, scale: -height)]
        let fits = centers.filter { center in
            (try? CircularCurveSegment(start: start, end: end, center: center, rotation: rotation,
                                      radius: radius, declaredLength: declaredLength, tolerances: options.tolerances)) != nil
        }
        guard fits.count == 1 else { throw GeometryError.invalidGeometry("Curve center cannot be uniquely derived.") }
        return fits[0]
    }
}
