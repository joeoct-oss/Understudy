// swift-tools-version: 6.0
import CompilerPluginSupport
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
    dependencies: [
        // The macros are built on swift-syntax. Any 6.x release works: body macros need 600.
        .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"700.0.0"),
    ],
    targets: [
        // Writes test doubles from the requirements they are given.
        .macro(
            name: "UnderstudyMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The spies the generated doubles call, and the macros' declarations.
        .target(name: "Understudy", dependencies: ["UnderstudyMacros"]),
        .testTarget(name: "UnderstudyTests", dependencies: ["Understudy"]),
        .testTarget(
            name: "UnderstudyMacrosTests",
            dependencies: [
                "UnderstudyMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
