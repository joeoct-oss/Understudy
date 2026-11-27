// swift-tools-version: 6.0
//
//  Package.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import PackageDescription

// Measures what Understudy costs at run time: spy calls, waits, the test clock and the traits.
// A package of its own that depends on Understudy by path, so no project that depends on
// Understudy resolves or builds it. Its benchmarks are tests, so the traits can run inside a real
// test, and they are built in debug, as a project builds its tests. `scripts/benchmark.sh` runs
// them and prints the table; run alone, each prints its own lines.
let package = Package(
    name: "UnderstudyBenchmarks",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "Understudy", path: "..")
    ],
    targets: [
        .testTarget(
            name: "Benchmarks",
            dependencies: [
                .product(name: "Understudy", package: "Understudy")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
