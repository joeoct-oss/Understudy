<p align="center">
  <img src=".github/assets/social-preview.png" alt="Understudy: pure Swift test doubles that stand in for the real thing. A mask with a dashed second mask behind it.">
</p>

# Understudy

Swift macros that write your test doubles: mark a requirement, and every call is kept and every answer is scripted by the test.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Spy on a function](#spy-on-a-function)
- [Script answers](#script-answers)
- [Properties](#properties)
- [Hold an async call](#hold-an-async-call)
- [Wait for a call](#wait-for-a-call)
- [Call order](#call-order)
- [Strict mocks](#strict-mocks)
- [Doubles for your own protocols](#doubles-for-your-own-protocols)
- [Spies by hand](#spies-by-hand)
- [What the macros refuse](#what-the-macros-refuse)

## Requirements

- Swift 6.0 or later, on Apple platforms (iOS 13, macOS 10.15, tvOS 13, watchOS 6, visionOS 1) and Linux.
- Swift Testing for `verify()`. Everything else works with any test framework.

## Install

Add the package, and add the product to your **test targets only**. Your shipped code never depends on Understudy.

```swift
dependencies: [
    .package(url: "https://github.com/joeoct-oss/Understudy", from: "0.3.0"),
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

## Quick start

Your app has a protocol:

```swift
protocol Catalog {
    func product(id: Int) -> Product?
}
```

In your test target, write a class that conforms to it. Put `@Understudy` on the class and `@Spied` on each function, with no body:

```swift
import Testing
import Understudy

@Understudy
final class SpyCatalog: Catalog {
    @Spied func product(id: Int) -> Product?
}

@Test
func showsTheProductItWasOpenedWith() {
    let catalog = SpyCatalog()
    catalog.productSpy.willReturn(.apple)

    let screen = ProductScreen(id: 7, catalog: catalog)

    let expectedIDs = [7]
    #expect(screen.title == "Apple")
    #expect(catalog.productSpy.calls == expectedIDs)
}
```

The macro writes the function's body and a spy named after it, `productSpy`. The compiler checks the double against your protocol, so it can't drift from the real thing.

## Spy on a function

Each spy keeps every call in order:

```swift
catalog.productSpy.calls      // [7, 9]
catalog.productSpy.callCount  // 2
catalog.productSpy.lastCall   // 9
catalog.productSpy.wasCalled  // true
```

A function with several parameters keeps them as a labelled tuple, so `search(for query: String, limit: Int)` gives `searchSpy.lastCall?.query` and `searchSpy.lastCall?.limit`. Overloads add their labels to the spy's name, such as `removeIdSpy` for `remove(id:)` and `removeNamedSpy` for `remove(named:)`.

## Script answers

A function that returns `Void` or an optional answers `()` or `nil` until you script it. Any other function needs its answer when the double is made, so a double can never be called with nothing scripted:

```swift
@Understudy
final class SpyPricing: Pricing {
    @Spied func price(of id: Int) -> Int
    @Spied func load(path: String) async throws -> String
}

let pricing = SpyPricing(price: 10, load: "")
```

Then change the answer at any point in the test:

```swift
pricing.priceSpy.willReturn(12)               // every later call
pricing.priceSpy.willReturnNext(1, then: 2)   // the next two calls, then back to 12
pricing.priceSpy.willAnswer { $0 * 100 }      // worked out from the input

pricing.loadSpy.willThrow(LoadError.offline)  // throwing functions
pricing.loadSpy.willGiveNext(.failure(LoadError.offline), then: .success("ok"))
```

## Properties

Mark a `var` with `@SpiedProperty` and give it only a type. A property that isn't optional takes its first value when the double is made:

```swift
@Understudy
final class SpySession: Session {
    @SpiedProperty var user: String
    @SpiedProperty var token: String?
}

let session = SpySession(user: "ana")
session.token = "abc"

session.tokenSpy.sets       // ["abc"]
session.userSpy.getCount    // how many times `user` was read
session.userSpy.willReturn("bo")
```

A set changes what later gets answer, as a real property would.

## Hold an async call

To check what the screen shows while it waits, hold the next call, then resume it with the answer you choose:

```swift
let refresh = catalog.refreshSpy.holdNextCall()
let task = Task { await screen.reload() }

await refresh.arrived()
#expect(screen.isLoading)

refresh.resume(returning: ())
await task.value
#expect(!screen.isLoading)
```

`resume(throwing:)` fails the call instead, and `resumeWithScriptedAnswer()` gives the answer the spy was scripted with. Calls you don't hold answer at once.

## Wait for a call

When the code under test calls the double from another task, wait for the call instead of sleeping:

```swift
screen.startPolling()

let id = try #require(await catalog.productSpy.nextCall())
#expect(id == 7)
```

`nextCall()` gives each call once, in order, or `nil` when none comes within the time you give it (`within:`, one second by default).

## Call order

To check the order of calls across spies, watch them with one `CallOrder`:

```swift
let order = CallOrder()
order.watch(store.saveSpy, as: "save")
order.watch(sync.sendSpy, as: "send")

checkout.complete()

let expectedOrder = ["save", "send"]
#expect(order.names == expectedOrder)
```

## Strict mocks

Tell a spy what to expect, and `verify()` reports every expected call that didn't happen and every call nobody expected, as Swift Testing issues at your test's line:

```swift
analytics.trackSpy.expect("checkout")
analytics.trackSpy.expect(times: 2) { $0.hasPrefix("view") }

checkout.complete()

analytics.trackSpy.verify()
```

`expectNoCalls()` makes any call a failure. A spy with no expectations stays lenient, so you only pay for strictness where you ask for it.

## Doubles for your own protocols

On a protocol in your own code, `@Understudy` writes the double next to it, named after the protocol with `Spy` added:

```swift
@Understudy
protocol Clock {
    var now: Double { get }
    func sleep(for seconds: Double) async
}

let clock = ClockSpy(now: 0)
```

This makes that protocol's target depend on Understudy, so prefer the class form when the protocol lives in shipped code. A protocol that inherits another (other than `Sendable` or `AnyObject`) needs the class form too, because the macro can't see the inherited requirements.

## Spies by hand

The macros write calls to `Spy`, `ThrowingSpy` and `PropertySpy`. Use them yourself for anything the macros don't cover:

```swift
final class SpyCatalog: Catalog {
    let productSpy = Spy<Int, Product?>(returning: nil)

    func product(id: Int) -> Product? {
        productSpy(id)
    }
}
```

`ThrowingSpy` does the same for functions that throw. In an async function, call `await productSpy.respond(to: id)` instead, so the test can hold the call. All three work under Swift 6 strict concurrency, in main-actor and `Sendable` doubles alike.

## What the macros refuse

Each of these is a compile error at the line it's about, with what to do instead. All of them can be written with [spies by hand](#spies-by-hand).

| Requirement | Why |
|---|---|
| Generic functions, `static` members | A stored spy has one input and output type, and belongs to one instance. |
| Typed `throws`, `rethrows` | The spy throws `any Error`, so it can't keep the promise. |
| `inout` or `@autoclosure` parameters, opaque (`some`) return types | A spy can't keep or hand back these safely. |
| `mutating` functions | The macro writes classes. |
| A parameter named `_` with no internal name | The body has no name to pass to the spy; name it. |
| Two requirements that would share a spy name | Rename one, or give the overloads different labels. |
| A protocol that inherits another, or has associated types, subscripts or initializers | The macro can't see or write them; use the class form or write it by hand. |

## License

MIT. See [LICENSE](LICENSE).
