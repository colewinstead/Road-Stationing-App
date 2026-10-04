import Foundation
import RoadStationCore
import RoadStationAppleCRS

// Full Phase 2A per-call context creation + database + operation + forward transform.
for epsg in [3857, 6507] {
    let transformer = try PROJProjectCoordinateTransformer(
        resolution: .identified(CoordinateReferenceSystem(epsgCode: epsg)), outputUnit: .linear(.usSurveyFoot))
    var samples: [Double] = []
    for index in 0..<210 {
        let start = Date()
        _ = try transformer.projectCoordinate(latitude: 32.4 + Double(index % 10) * 0.000001, longitude: -89.2)
        if index >= 10 { samples.append(Date().timeIntervalSince(start) * 1000) }
    }
    samples.sort()
    let mean = samples.reduce(0, +) / Double(samples.count)
    print("EPSG:\(epsg) n=\(samples.count) mean=\(mean)ms p50=\(samples[100])ms p95=\(samples[190])ms max=\(samples.last!)ms; 1Hz budget=1000ms")
}
