<p align="center">
  <img src=".github/assets/social-preview.png" alt="Understudy: pure Swift test doubles that stand in for the real thing. A mask with a dashed second mask behind it.">
</p>

# Understudy

**Mocks and fakes for your Swift tests, written for you.** Mark the functions and properties your fake stands in for, and Understudy's Swift macros record every call and answer the way your test says.

These stand-ins are called *test doubles*, as a stunt double stands in for an actor: a test uses one in place of a real dependency, such as a network client, a database or a clock, so the test decides what it answers and can check how it was called.

It has two tools, in two products:

- **Spies** (`Understudy`): `@GenerateSpies` writes a test double for your protocol. Each function and property gets a spy that records its calls and gives scripted answers.
- **Sample values** (`UnderstudySamples`): `@Sample` writes `sample(...)` for a struct, so a test gets a complete value in one call.

**Contents:** [Install](#install) · [Quick start](#quick-start) · [Spies](#spies) · [Sample values](#sample-values) · [What the macros refuse](#what-the-macros-refuse)

## Install

Understudy needs Swift 6.0 or later and runs on Apple platforms (iOS 13, macOS 10.15, tvOS 13, watchOS 6, visionOS 1) and Linux. Its one dependency is swift-syntax 602 or later, which SwiftPM picks for you.

Add the package, then add `Understudy` to your **test targets**. Your shipped code never depends on it.

```swift
dependencies: [
    .package(url: "https://github.com/joeoct-oss/Understudy", from: "0.5.0"),
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

To use `@Sample`, add `UnderstudySamples` to the target that declares your structs, even an app target. See [Sample values](#sample-values).

## Quick start

Your app has a protocol:

```swift
protocol Catalog {
    func product(id: Int) -> Product?
}
```

In your test target, write a class that conforms to it. Put `@GenerateSpies` on the class and `@Spied` on each function, with no body:

```swift
import Testing
import Understudy

@GenerateSpies
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

The macro writes the function's body and a spy named after it: `productSpy`. Because the class conforms to your protocol, the compiler keeps the double in step with the real thing.

## Spies

- [Read the calls](#read-the-calls)
- [Script answers](#script-answers)
- [Typed throws](#typed-throws)
- [Properties](#properties)
- [Subscripts](#subscripts)
- [Static members](#static-members)
- [Async calls](#async-calls)
- [Call order](#call-order)
- [Strict mocks](#strict-mocks)
- [Reset](#reset)
- [Generic functions](#generic-functions)
- [Actors](#actors)
- [Doubles next to your protocol](#doubles-next-to-your-protocol)
- [Spies by hand](#spies-by-hand)

### Read the calls

Each spy keeps every call, in order:

```swift
catalog.productSpy.calls      // [7, 9]
catalog.productSpy.callCount  // 2
catalog.productSpy.lastCall   // 9
catalog.productSpy.wasCalled  // true
```

A function with several parameters records them as a labelled tuple: `search(for query: String, limit: Int)` gives `searchSpy.lastCall?.query` and `searchSpy.lastCall?.limit`. Overloads add their labels to the spy's name, such as `removeIdSpy` for `remove(id:)` and `removeNamedSpy` for `remove(named:)`.

### Script answers

Every function answers something from the start, so a double is never called with nothing to answer. `Void` answers `()` and an optional answers `nil`. A string answers `""`, a number `0`, a `Bool` `false`, and an array, dictionary or set answers empty, unless you pass another answer when you make the double. Any other type, such as your own `Product`, has to be passed:

```swift
@GenerateSpies
final class SpyPricing: Pricing {
    @Spied func price(of id: Int) -> Int
    @Spied func product(id: Int) -> Product
}

let pricing = SpyPricing(product: .apple)              // price answers 0
let pricier = SpyPricing(price: 10, product: .apple)   // price answers 10
```

The macro reads the type as you wrote it, so `Swift.String`, or a typealias of `String`, has to be passed too.

Change the answer at any point in the test:

```swift
pricing.priceSpy.willReturn(12)               // every later call
pricing.priceSpy.willReturnNext(1, then: 2)   // the next two calls, then back to 12
pricing.priceSpy.willAnswer { $0 * 100 }      // worked out from the input

loader.loadSpy.willThrow(LoadError.offline)   // a function that throws
loader.loadSpy.willGiveNext(.failure(LoadError.offline), then: .success("ok"))
```

### Typed throws

A function that throws one error type, such as `throws(AuthError)`, works like any function that throws. Script its error the same way:

```swift
@GenerateSpies
final class SpyAuth: AuthService {
    @Spied func signIn(email: String, password: String) async throws(AuthError) -> Account
}

auth.signInSpy.willThrow(AuthError.wrongPassword)   // the caller catches an AuthError
```

`willThrow` takes any error, so the type is checked when the test runs: an error of another type stops the test with a message that names the spy and both types.

### Properties

Mark a `var` with `@SpiedProperty` and give it a type. Give it a first value too, or pass one when the double is made. Without either, it starts as `nil`, `""`, `0`, `false` or empty, as a function's answer does, and any other type has to be passed:

```swift
@GenerateSpies
final class SpySession: Session {
    @SpiedProperty var user: String
    @SpiedProperty var token: String?
    @SpiedProperty var theme: String = "light"   // starts as "light"; the init doesn't ask
}

let session = SpySession(user: "ana")
session.token = "abc"

session.tokenSpy.sets       // ["abc"]
session.userSpy.getCount    // how many times `user` was read
session.userSpy.willReturn("bo")
```

A set changes what later gets answer, as a real property would.

`@SpiedProperty` works in a class, a `Sendable` class and an actor. For a double written by hand, with no macro, use the `@Recorded` property wrapper. `$user` is its spy:

```swift
@Recorded var user = "ana"

session.$user.sets
```

`@Recorded` can't go in an actor, where reading `$user` would need `await`, or in a `Sendable` class, which can't hold the wrapper's `var` storage.

### Subscripts

Swift needs a body for a subscript in a class, so mark its `get`, and its `set` if it has one, with `@Spied` and give each an empty body:

```swift
@GenerateSpies
final class SpyList: ItemList {
    subscript(index: Int) -> Item { @Spied get {} @Spied set {} }
}

let list = SpyList(subscript: .apple)
list.subscriptSpy.willReturn(.pear)
list[2] = .plum

list.subscriptSpy.calls                    // the index of every get
list.subscriptSetSpy.calls.map(\.index)    // [2]
```

Gets go to `subscriptSpy` and sets to `subscriptSetSpy`, which keeps the index and the `newValue`. A get-only subscript has only `subscriptSpy`. Several indices are kept as a labelled tuple, and overloads add the index names, such as `subscriptRowColumnSpy` for `subscript(row:column:)`.

`@Spied` on a `get` or `set` needs Swift 6.4 or later. With an older Swift, use [a double next to your protocol](#doubles-next-to-your-protocol), whose subscript requirements are written the same way on every Swift version.

### Static members

`@Spied static func` and `@SpiedProperty static var` work too. A static spy has no initializer to take its first answer, so it starts as `nil`, `()`, `""`, `0`, `false` or empty, and the test scripts any other with `willReturn`:

```swift
@GenerateSpies
final class SpyClock: Clock {
    @Spied static func now() -> Date?
}

@Suite(.freshSpies(SpyClock.self))
struct GreetingTests {
    @Test
    func showsTodaysDate() {
        SpyClock.nowSpy.willReturn(.distantPast)
    }
}
```

Put `.freshSpies(...)` on the suite or the test: each test then gets its own static spies, so tests that run in parallel never see each other's calls or answers. Without it, every test shares one set of static spies. A static requirement whose answer has no obvious first value, such as `Date`, is refused; make it optional.

Its limits:
- **Swift 6.1 or later** for `.freshSpies(...)`, which is a test scoping trait.
- **Tasks that leave the test** don't see its spies: a detached task or Dispatch work reads the shared ones, because task locals don't cross them. Child tasks and `async let` do see them.
- **A spy class next to a protocol** can't be named in a trait, because Swift doesn't look into macro expansions from a macro's arguments. Run the test's body in `try await ClockSpy.withFreshSpies { ... }` instead.

### Async calls

**Hold a call** to check what the screen shows while it waits, then resume it with the answer you choose:

```swift
let refresh = catalog.refreshSpy.holdNextCall()
let task = Task { await screen.reload() }

await refresh.arrived()
#expect(screen.isLoading)

refresh.resume(returning: ())
await task.value
#expect(!screen.isLoading)
```

`resume(throwing:)` fails the call instead, and `resumeWithScriptedAnswer()` gives the scripted answer. Calls you don't hold answer at once.

**Wait for a call** made from another task, instead of sleeping:

```swift
screen.startPolling()

let id = try #require(await catalog.productSpy.nextCall())
#expect(id == 7)
```

`nextCall()` gives each call once, in order, or `nil` when none comes in time (`within:`, one second by default).

### Call order

To check the order of calls across spies, watch them with one `CallOrder`:

```swift
let order = CallOrder {
    Watched(store.saveSpy, as: "save")
    Watched(sync.sendSpy, as: "send")
}

checkout.complete()

let expectedOrder = ["save", "send"]
#expect(order.names == expectedOrder)
```

`order.watch(spy, as: name)` adds a spy later. The order sees only calls made after it starts watching.

### Strict mocks

Tell a spy what to expect, and `verify()` reports every expected call that didn't happen and every call nobody expected, as Swift Testing issues at your test's line:

```swift
analytics.trackSpy.expect("checkout")
analytics.trackSpy.expect(times: 2) { $0.hasPrefix("view") }

checkout.complete()

analytics.trackSpy.verify()
```

`expectNoCalls()` makes any call a failure. A spy with no expectations stays lenient. `verify()` needs Swift Testing; everything else works with any test framework.

### Reset

`reset()` forgets what happened so far (the calls, a property's gets and sets, where `nextCall()` was, and the expectations) and keeps the scripted answers. Use it to check one step of a test at a time:

```swift
checkout.addItem(.apple)
analytics.trackSpy.reset()

checkout.complete()

let expectedEvents = ["checkout"]
#expect(analytics.trackSpy.calls == expectedEvents)
```

A `CallOrder` keeps the names it has; make a new one for the next step.

### Generic functions

A generic function can be `@Spied` when each generic parameter is a whole type (`T`), or sits inside an array, an optional, a dictionary's value or a set (`[T]`, `T?`, `[String: T]`, `Set<T>`). The spy records `T` as `any` of its constraints, or `Any`, in the same container, and casts the answer back to the type the caller asks for:

```swift
@GenerateSpies
final class SpyCache: Cache {
    @Spied func value<Value: Decodable>(for key: String) -> Value?
}

cache.valueSpy.willReturn(42)
let count: Int? = cache.value(for: "count")   // 42
```

```swift
@Spied func tags<T: Tag>(_ items: [T]) -> [T]   // tagsSpy records [any Tag]

let tags: [Label] = session.tags([.new])
```

A set is recorded as `Set<AnyHashable>`, because `any Tag` can't go in a set.

An answer of the wrong type stops the test with a message naming the spy and both types.

### Actors

`@GenerateSpies` works on an actor as on a class. The spies are `nonisolated`, so a test reads them without `await`:

```swift
@GenerateSpies
actor SpyStore: Store {
    @Spied func save(_ item: Item) async throws
}

try await store.save(.apple)
#expect(store.saveSpy.callCount == 1)
```

### Doubles next to your protocol

On a protocol in your own code, `@GenerateSpies` writes the double next to it, named with `Spy` added:

```swift
@GenerateSpies
protocol Clock {
    var now: Double { get }
    func sleep(for seconds: Double) async
}

let clock = ClockSpy(now: 0)
```

That protocol's target then depends on Understudy, so prefer the class form for protocols in shipped code. A protocol that inherits `Actor` gets an actor spy. One that inherits any other protocol, except `Sendable` and `AnyObject`, needs the class form, because the macro can't see the inherited requirements.

### Spies by hand

The macros write calls to `Spy`, `ThrowingSpy` and `PropertySpy`. Use them yourself for anything the macros don't cover:

```swift
final class SpyCatalog: Catalog {
    let productSpy = Spy<Int, Product?>(returning: nil)

    func product(id: Int) -> Product? {
        productSpy(id)
    }
}
```

`ThrowingSpy` does the same for functions that throw. In an async function, call `await productSpy.respond(to: id)`, so the test can hold the call. All three work under Swift 6 strict concurrency, in main-actor and `Sendable` doubles alike.

## Sample values

`@Sample` on a struct writes `static func sample(...)`, with a default for every property, so a test names only the values it is about:

```swift
import UnderstudySamples

@Sample
public struct Product: Equatable {
    let id: UUID
    let name: String
    let price: Decimal
    var stock: Int = 5
    @SampleDefault("EGP") let currency: String
    let seller: Seller    // Seller has @Sample too
}

// In a test
let free = Product.sample(price: 0)
```

Add `UnderstudySamples` to the target that declares the struct. It knows nothing about spies, and `sample(...)` is compiled in debug builds only, so a release build carries none of it:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "UnderstudySamples", package: "Understudy"),
    ]
),
```

The defaults:

| Type | Default |
|---|---|
| `String`, `Substring` | `""` |
| Numbers, `Decimal` | `0` |
| `Bool` | `false` |
| Optionals | `nil` |
| Arrays, dictionaries, sets | empty |
| `Date` | `Date(timeIntervalSince1970: 0)` |
| `UUID` | all zeros |
| `URL` | `https://example.com` |
| Any other type | its own `.sample()` |

A property's own initial value is its default, and `@SampleDefault(value)` sets another. A `let` with a value, a computed property and a static one aren't parameters. `sample(...)` is as visible as the struct.

Its limits:

- **Structs only**, with their memberwise initializer (or one that takes every stored property).
- **Every stored property needs a written type**, such as `var stock: Int = 5`.
- **A type with no default and no `@Sample`**, such as a closure, stops the build with "has no member 'sample'". Give it one: `@SampleDefault(Money(amount: 0))`.
- **A nested type must be as visible as the struct**, so a public struct can't default to an internal type's `.sample()`.

## What the macros refuse

Each of these is a compile error at the line it's about, saying what to do instead. Where there is one clear fix, such as `let` to `var`, removing a `@Spied` function's body, naming a parameter, adding a property's type, or `@Recorded` to `@SpiedProperty` in an actor or a `Sendable` class, your editor offers it as a fix-it. You can write any of them with [spies by hand](#spies-by-hand).

| Requirement | Why |
|---|---|
| A `static` member whose answer has no obvious first value | No initializer takes its first answer; make it optional. |
| A generic parameter inside a closure, a tuple or another generic type (`Result<T, E>`), a `where` clause, a parameter pack | A spy records one input type, and only these containers can be recorded and cast back. |
| `rethrows`, or a function that throws its own generic type (`throws(E)` with `<E: Error>`) | The spy can't tell when the function may throw, or which type it throws. |
| `inout` or `@autoclosure` parameters, opaque (`some`) return types | A spy can't keep or hand back these safely. |
| `mutating` functions | The macro writes classes and actors. |
| A parameter named `_` with no internal name | The body has no name to pass to the spy; name it. |
| Two requirements that would share a spy name | Rename one, or give the overloads different labels. |
| A protocol that inherits another, or has associated types or initializers; a generic, `static`, `async` or throwing subscript | The macro can't see or write them; use the class form or write it by hand. |

## License

MIT. See [LICENSE](LICENSE).
