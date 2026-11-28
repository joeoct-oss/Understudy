// swift-tools-version: 6.0
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
