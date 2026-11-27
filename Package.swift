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
        .library(name: "UnderstudySamples", targets: ["UnderstudySamples"]),
    ],
    dependencies: [
        // The macros are built on swift-syntax, from 602: 600 lacks the generic parameter
        // specifier the macros read, and 601 reports a misplaced `@SpiedProperty` differently.
        .package(url: "https://github.com/swiftlang/swift-syntax", "602.0.0"..<"700.0.0")
    ],
    targets: [
        // Writes test doubles from the requirements they are given.
        .macro(
            name: "UnderstudyMacros",
            dependencies: [
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
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
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        // Writes `sample(...)` for structs. Knows nothing about spies.
        .macro(
            name: "UnderstudySamplesMacros",
            dependencies: [
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The `@Sample` macro's declarations, for app targets as well as test targets.
        .target(name: "UnderstudySamples", dependencies: ["UnderstudySamplesMacros"]),
        .testTarget(name: "UnderstudySamplesTests", dependencies: ["UnderstudySamples"]),
        .testTarget(
            name: "UnderstudySamplesMacrosTests",
            dependencies: [
                "UnderstudySamplesMacros",
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
