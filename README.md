# Understudy

Pure Swift building blocks for test doubles. A `Spy` keeps every call a test double receives and answers as the test scripts, so you can write stubs, spies, mocks and fakes by hand in a few lines. No macros, no code generation, no dependencies.

## Install

Add the package, and the product to your test targets:

```swift
dependencies: [
    .package(url: "https://github.com/joeoct-oss/Understudy", from: "0.1.0"),
],
targets: [
    .testTarget(
        name: "AppTests",
        dependencies: [
            "App",
            .product(name: "Understudy", package: "Understudy"),
        ]
    ),
]
```

## Example

```swift
import Testing
import Understudy

final class SpyCatalog: Catalog {
    let productByID = Spy<Int, Product?>(returning: nil)

    func product(id: Int) -> Product? {
        productByID(id)
    }
}

@Test
func showsTheProductItWasOpenedWith() {
    let catalog = SpyCatalog()
    catalog.productByID.willReturn(.apple)

    let screen = ProductScreen(id: Product.apple.id, catalog: catalog)

    let expectedIDs = [Product.apple.id]
    #expect(screen.title == "Apple")
    #expect(catalog.productByID.calls == expectedIDs)
}
```

`ThrowingSpy` does the same for requirements that throw. Both work with Swift 6 strict concurrency, from main-actor and `Sendable` test doubles alike.

## License

MIT. See [LICENSE](LICENSE).
