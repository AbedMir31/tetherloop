// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TetherLoop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TetherLoop", targets: ["TetherLoop"]),
        .executable(name: "GenerateScreenshots", targets: ["GenerateScreenshots"]),
        .library(name: "TetherLoopCore", targets: ["TetherLoopCore"])
    ],
    targets: [
        .target(
            name: "TetherLoopCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "TetherLoop",
            dependencies: ["TetherLoopCore"]
        ),
        .executableTarget(
            name: "GenerateScreenshots",
            dependencies: ["TetherLoopCore"]
        ),
        .testTarget(
            name: "TetherLoopTests",
            dependencies: ["TetherLoopCore"]
        )
    ]
)
