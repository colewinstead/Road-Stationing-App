// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoadStationCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoadStationCore", targets: ["RoadStationCore"]),
        .executable(name: "roadstation-validate", targets: ["RoadStationCLI"])
    ],
    targets: [
        .target(name: "RoadStationCore", path: "RoadStation/Core"),
        .executableTarget(name: "RoadStationCLI", dependencies: ["RoadStationCore"], path: "RoadStation/CLI"),
        .testTarget(name: "RoadStationCoreTests", dependencies: ["RoadStationCore"],
                    path: "Tests", resources: [.copy("Fixtures")])
    ]
)
