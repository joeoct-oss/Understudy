# Double a protocol that declares an initializer

Write a double for a protocol with an `init` requirement, and check what your code made it with.

## Overview

Code that makes its own dependencies, through a type it was given, calls the protocol's `init`. A double then has to answer that `init`, and the test wants to know what it was called with.

### Next to the protocol

On a protocol in your own code, `@GenerateSpies` writes each `init` the protocol declares. The spy class gets that `init`, which builds the double with its first answers, and a static spy that records what each call was given, named like a function's: `initSpy`.

```swift
@GenerateSpies
protocol Session {
    init(user: String) throws

    func ping() -> Int
}

func start<Made: Session>(_ type: Made.Type) throws -> Made {
    try Made(user: "ana")
}
```

`initSpy` is a static spy, so the test runs its body in `withFreshSpies`, and parallel tests never see each other's calls. An `init` that throws has a ``ThrowingSpy``, so the test can make it throw:

```swift
try await SessionSpy.withFreshSpies {
    _ = try start(SessionSpy.self)

    let expectedUsers = ["ana"]
    #expect(SessionSpy.initSpy.calls == expectedUsers)

    SessionSpy.initSpy.willThrow(SessionError.locked)
    #expect(throws: SessionError.locked) { try start(SessionSpy.self) }
}
```

The spy's own initializer, `SessionSpy(ping: 3)`, is unchanged and records nothing. The protocol's `init` can't take answers, so every other requirement needs an obvious first answer, such as `0` or `nil`; make the rest optional. A failable or generic `init`, and one next to an associated type, need the class form below.

### In a class double

A class that conforms to the protocol writes the `init` itself, as a `convenience init` that makes the double with the answers it wants. To record the call, it adds a `@Spied static func` and calls it:

```swift
@GenerateSpies
final class SpyRenderer: Renderer {
    convenience init(title: String) {
        self.init()
        Self.made(title: title)
    }

    @Spied static func made(title: String)
    @Spied func draw()
}
```

The test reads `SpyRenderer.madeSpy`, with `.freshSpies(SpyRenderer.self)` on the suite. See <doc:GiveEachTestItsOwnStaticSpies>.

## Where the rules live

- [Doubles next to your protocol](https://github.com/joeoct-oss/Understudy#doubles-next-to-your-protocol) in the README, and its table of what the macros refuse.
