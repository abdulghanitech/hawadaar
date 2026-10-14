// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AirBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirBar", targets: ["AirBar"]),
        .library(name: "AirBarCore", targets: ["AirBarCore"]),
    ],
    targets: [
        .target(name: "AirBarCore"),
        .executableTarget(name: "AirBar", dependencies: ["AirBarCore"]),
        .testTarget(name: "AirBarCoreTests", dependencies: ["AirBarCore"]),
    ]
)
