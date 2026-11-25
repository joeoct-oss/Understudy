<p align="center">
  <img src=".github/assets/social-preview.png" alt="Understudy: pure Swift test doubles that stand in for the real thing. A mask with a dashed second mask behind it.">
</p>

# Understudy

Test doubles for Swift, written by Swift macros. Put `@Understudy` on a double in your test target and it writes a spy for every requirement: each call is kept, and each answer is scripted by the test. Stubs, spies, mocks and fakes, in a line per requirement, checked by the compiler against your protocol.

## Install

Add the package, and the product to your test targets:

```swift
dependencies: [
    .package(url: "https://github.com/joeoct-oss/Understudy", from: "0.2.0"),
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

Write the double in your test target. Mark each requirement `@Spied` and give it no body; the macro writes the body and a spy named after the requirement:

```swift
import Testing
import Understudy

@Understudy
final class SpyCatalog: Catalog {
    @Spied func product(id: Int) -> Product?
    @Spied func refresh() async throws
}

@Test
func showsTheProductItWasOpenedWith() {
    let catalog = SpyCatalog()
    catalog.productSpy.willReturn(.apple)

    let screen = ProductScreen(id: Product.apple.id, catalog: catalog)

    let expectedIDs = [Product.apple.id]
    #expect(screen.title == "Apple")
    #expect(catalog.productSpy.calls == expectedIDs)
}
```

Your shipped code doesn't change and never depends on Understudy. A requirement that returns something other than `Void` or an optional needs its answer when the double is created, such as `SpyClock(now: 10)`, so a double can't be called with nothing scripted. Overloads add their argument labels, such as `removeIdSpy` and `removeNamedSpy`.

On a protocol you own, `@Understudy` writes the spy class next to it instead, such as `ClockSpy` for `Clock`. That protocol's target then depends on Understudy. A protocol that inherits another (other than `Sendable` or `AnyObject`) needs the class form, because the macro can't see the inherited requirements.

### Spies by hand

The macros write calls to `Spy` and `ThrowingSpy`, which you can also use on their own, for a double the macros don't cover, such as one with properties or generic requirements:

```swift
final class SpyCatalog: Catalog {
    let productSpy = Spy<Int, Product?>(returning: nil)

    func product(id: Int) -> Product? {
        productSpy(id)
    }
}
```

`ThrowingSpy` does the same for requirements that throw. Both work with Swift 6 strict concurrency, from main-actor and `Sendable` test doubles alike.

## License

MIT. See [LICENSE](LICENSE).
