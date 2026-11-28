// swift-tools-version: 6.0
//
//  Package.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import PackageDescription

let package = Package(
    name: "Restaurant",
    dependencies: [
        .package(url: "https://github.com/joeoct-oss/Understudy", from: "1.0.1")
    ],
    targets: [
        .target(name: "Restaurant"),
        .testTarget(
            name: "RestaurantTests",
            dependencies: [
                "Restaurant",
                .product(name: "Understudy", package: "Understudy"),
            ]
        ),
    ]
)
