// swift-tools-version: 6.0
import PackageDescription

// The package's own tests, built for iOS, tvOS, watchOS and visionOS. The code the macros write
// compiles in the user's test target, for the user's platform and its lowest version, so this
// proves it builds there with Apple's toolchain. The macro tests stay out: they import the macro
// targets, which Xcode builds for the Mac only. The test folders are links to the package's own,
// so there is one copy of each test. The platforms are the package's own, from its Package.swift:
// a change there changes them here in the same pull request. CI builds it with the package's
// Package.resolved (.github/workflows/apple.yml).
let package = Package(
    name: "ApplePlatforms",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    dependencies: [.package(name: "Understudy", path: "..")],
    targets: [
        .testTarget(name: "UnderstudyTests", dependencies: [.product(name: "Understudy", package: "Understudy")]),
        .testTarget(
            name: "UnderstudySamplesTests",
            dependencies: [.product(name: "UnderstudySamples", package: "Understudy")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
