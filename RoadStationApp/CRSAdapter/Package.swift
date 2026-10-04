// swift-tools-version: 6.0
import PackageDescription

// Apple-only dependency boundary. The root/core package has no external dependency.
let package = Package(
    name: "RoadStationAppleCRS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoadStationAppleCRS", targets: ["RoadStationAppleCRS"]),
        .library(name: "RoadStationCRSCatalog", targets: ["RoadStationCRSCatalog"]),
        .library(name: "RoadStationFieldPosition", targets: ["RoadStationFieldPosition"]),
        .executable(name: "roadstation-transform-benchmark", targets: ["RoadStationTransformBenchmark"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/ngageoint/projections-ios.git", exact: "3.0.0"),
        .package(url: "https://github.com/ngageoint/PROJ.git", exact: "9.4.2")
    ],
    targets: [
        .target(name: "ProjectionResources", dependencies: [
            .product(name: "Projections", package: "projections-ios")
        ]),
        .target(name: "RoadStationAppleCRS", dependencies: [
            .product(name: "RoadStationCore", package: "Road-Stationing-App"),
            .product(name: "Projections", package: "projections-ios"),
            .product(name: "proj", package: "PROJ"), "ProjectionResources"
        ]),
        .testTarget(name: "RoadStationAppleCRSTests", dependencies: ["RoadStationAppleCRS"]),
        .target(name: "RoadStationCRSCatalog", dependencies: ["ProjectionResources",
            .product(name: "proj", package: "PROJ"), .product(name: "RoadStationCore", package: "Road-Stationing-App")], resources: [.process("Resources")]),
        .testTarget(name: "RoadStationCRSCatalogTests", dependencies: ["RoadStationCRSCatalog"]),
        .target(name: "RoadStationFieldPosition", dependencies: ["RoadStationAppleCRS", "RoadStationCRSCatalog",
            .product(name: "RoadStationCore", package: "Road-Stationing-App")]),
        .testTarget(name: "RoadStationFieldPositionTests", dependencies: ["RoadStationFieldPosition"]),
        .executableTarget(name: "RoadStationTransformBenchmark", dependencies: ["RoadStationAppleCRS"])
    ]
)
