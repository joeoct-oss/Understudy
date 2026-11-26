// swift-tools-version: 6.0
//
//  Package.swift
//  ExpansionRecord
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import PackageDescription

// Prints what Understudy's macros write. A package of its own, so no project that depends on
// Understudy builds it. `scripts/compare-expansions.sh` copies it to a scratch folder, adds the
// macro sources of the commit it records under `Sources/`, without the compiler plugins' entry
// points, and builds them as plain libraries, because a macro target can't be linked into a tool.
let package = Package(
    name: "ExpansionRecord",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", "602.0.0"..<"700.0.0"),
    ],
    targets: [
        .target(name: "UnderstudyMacros", dependencies: macroDependencies),
        .target(name: "UnderstudySamplesMacros", dependencies: macroDependencies),
        .executableTarget(
            name: "ExpansionRecord",
            dependencies: [
                "UnderstudyMacros",
                "UnderstudySamplesMacros",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            ] + macroDependencies
        ),
    ],
    swiftLanguageModes: [.v6]
)

/// The swift-syntax libraries the macros are built on.
var macroDependencies: [Target.Dependency] {
    [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
    ]
}
