// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RimpyLight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RimpyLight",
            path: "Sources/RimpyLight"
        ),
        .testTarget(
            name: "RimpyLightTests",
            dependencies: ["RimpyLight"],
            path: "Tests/RimpyLightTests"
        ),
    ]
)
