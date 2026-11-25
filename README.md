# Understudy

Small, pure Swift building blocks for test doubles: spies that keep every call and answer as the test scripts. Write your fakes, stubs, mocks and spies by hand in a few lines each, with no macros, no code generation and no dependencies.

- **Pure Swift.** Foundation only. No macros, no swift-syntax, nothing added to your build but one small target.
- **Swift 6 ready.** Spies carry no actor: they work in `@MainActor` doubles that take values which aren't `Sendable`, and in `Sendable` doubles called from many tasks.
- **Safe by construction.** A spy that returns something gets its answer when it is created, so a double can never be called with nothing scripted.
- **Any test framework.** Check calls with Swift Testing's `#expect` or XCTest's `XCTAssert`; the package has no assertion API of its own.
- **Every platform.** iOS 13, macOS 10.15, tvOS 13, watchOS 6, visionOS 1 and Linux.

## Install

Add the package, and the product to your **test targets only**:

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

## In 30 seconds

```swift
import Testing
import Understudy

protocol Catalog {
    func product(id: Int) -> Product?
}

// One spy per requirement; the requirement's body calls it.
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

    #expect(screen.title == "Apple")
    let expected = [Product.apple.id]
    #expect(catalog.productByID.calls == expected)
}
```

## Scripting answers

| You want | Write |
|---|---|
| The same answer for every call | `Spy<Int, Product?>(returning: nil)`, or later `spy.willReturn(.apple)` |
| Different answers for the next calls, then the standing one | `spy.willReturn(.apple, then: .pear, nil)` |
| An answer worked out from the input | `Spy<Int, Int> { id in id * 2 }`, or later `spy.willAnswer { id in id * 2 }` |
| Nothing, for a requirement that returns `Void` | `Spy<Event, Void>()` |
| A requirement that throws | `ThrowingSpy<Request, Data>(throwing: URLError(.notConnectedToInternet))`, `spy.willThrow(_:)`, `spy.willGive(.success(data), then: .failure(error))` |

`willReturn(_:)` and `willAnswer(_:)` replace the standing answer and drop any answers still queued.

## Checking calls

| Property | What it gives |
|---|---|
| `calls` | Every input, oldest first |
| `callCount` | How many calls |
| `lastCall` | The most recent input, or `nil` |
| `wasCalled` | Whether it was called at all |

A requirement with several parameters records a labelled tuple, and the test reads the part it checks:

```swift
let requireAccount = Spy<(reason: SignInReason, then: () -> Void), Void>()

func requireAccount(for reason: SignInReason, then action: @escaping () -> Void) {
    requireAccount((reason: reason, then: action))
}

// In the test:
#expect(gate.requireAccount.calls.map(\.reason) == expectedReasons)
gate.requireAccount.lastCall?.then()   // the test decides when the held action runs
```

## Spies, stubs, mocks and fakes

Each test picks the double its case needs; a spy is the building block for all four.

- **Stub**: gives set answers. A spy with a standing answer, whose calls the test ignores.
- **Spy**: keeps what it was called with, and the test reads it after.
- **Mock**: a spy the test checks against what it expected, with `#expect(spy.calls == expected)`.
- **Fake**: real, simpler behaviour written by hand, such as an in-memory store. Hold a spy inside when the test also needs the calls:

```swift
final class FakeAccountGate: AccountGate {
    let isSignedIn: Bool
    let requireAccount = Spy<SignInReason, Void>()

    init(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
    }

    func requireAccount(for reason: SignInReason, then action: () -> Void) {
        requireAccount(reason)
        guard isSignedIn else {
            return
        }
        action()
    }
}
```

## Concurrency

- A spy is `Sendable` when its input and output are, so a `Sendable` double can hold it. Its state sits behind a lock, and calls from many tasks are all kept.
- A spy has no actor, so a `@MainActor` double can hold one that records classes and closures.
- Answer closures are `@Sendable`. An answer that needs main-actor state belongs in the double's own method, next to the spy call.
- An `async` requirement calls the spy like any other: `func load() async throws -> Data { try loadCalls() }`.

## License

MIT. See [LICENSE](LICENSE).
