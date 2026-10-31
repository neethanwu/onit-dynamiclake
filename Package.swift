// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnitLake",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "OnitLake",
            path: "Sources/OnitLake"
        ),
        .testTarget(
            name: "OnitLakeTests",
            dependencies: ["OnitLake"],
            path: "Tests/OnitLakeTests"
        ),
    ]
)
