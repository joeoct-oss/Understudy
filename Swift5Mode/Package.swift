// swift-tools-version: 6.0
import PackageDescription

// The package's own tests, built as a project in Swift 5 language mode would build them. The code
// the macros write compiles in the language mode of the target that uses them, so this proves it
// builds and behaves the same in a Swift 5 mode project. Understudy itself builds in Swift 6 mode,
// as it does in any project. The test folders are links to the package's own, so there is one copy
// of each test. CI runs it with the package's Package.resolved (the "Swift 5 language mode" job).
let package = Package(
    name: "Swift5Mode",
    dependencies: [.package(name: "Understudy", path: "..")],
    targets: [
        .testTarget(name: "UnderstudyTests", dependencies: [.product(name: "Understudy", package: "Understudy")]),
        .testTarget(
            name: "UnderstudySamplesTests",
            dependencies: [.product(name: "UnderstudySamples", package: "Understudy")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
