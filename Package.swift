// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AIMClaude",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "AIMCore"),
        .executableTarget(name: "AIMClaude", dependencies: ["AIMCore"]),
        .testTarget(name: "AIMCoreTests", dependencies: ["AIMCore"]),
    ]
)
