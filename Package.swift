// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Understudy",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Understudy", targets: ["Understudy"]),
    ],
    targets: [
        // Foundation only, so it builds and tests on Linux and every Apple platform.
        .target(name: "Understudy"),
        .testTarget(name: "UnderstudyTests", dependencies: ["Understudy"]),
    ],
    swiftLanguageModes: [.v6]
)
