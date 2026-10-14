// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hawadaar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hawadaar", targets: ["Hawadaar"]),
        .library(name: "HawadaarCore", targets: ["HawadaarCore"]),
    ],
    targets: [
        .target(name: "HawadaarCore"),
        .executableTarget(name: "Hawadaar", dependencies: ["HawadaarCore"]),
        .testTarget(name: "HawadaarCoreTests", dependencies: ["HawadaarCore"]),
    ]
)
