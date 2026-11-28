# Give each test its own static spies

Keep tests that run in parallel from seeing each other's calls to a static requirement.

## Overview

A static requirement, such as `static func hour()`, has one spy for the whole type, and Swift Testing runs tests in parallel. Without care, one test's scripted answer or calls show up in another. Understudy keeps the static spies in a box per test.

### Name the double in a trait

On a class double, put `.freshSpies(...)` on the suite or the test. Each test then gets its own static spies, which every task it starts sees too:

```swift
@GenerateSpies
final class SpySundial: Sundial {
    @Spied static func hour() -> Int?
}

@Suite("Greetings", .freshSpies(SpySundial.self))
struct GreetingTests {
    @Test("Greets the morning")
    func greetsTheMorning() {
        SpySundial.hourSpy.willReturn(8)

        #expect(greeting(by: SpySundial.self) == "Good morning")
    }
}
```

A static spy has no initializer to take its first answer, so it starts as `nil`, `()`, `""`, `0`, `false` or empty, and the test scripts any other with `willReturn`.

### Run the body with fresh spies

A trait can't name a spy class the macro writes next to a protocol, because Swift doesn't look into macro expansions from a macro's arguments. Run the test's body in `withFreshSpies` instead, which does the same for the code inside it:

```swift
try await MetronomeSpy.withFreshSpies {
    MetronomeSpy.beatSpy.willReturn(3)

    #expect(MetronomeSpy.beat() == 3)
}
```

A detached task or Dispatch work started from the test reads the shared spies, because task locals don't reach them. Child tasks and `async let` see the test's own.

## Where the rules live

- [Static members](https://github.com/joeoct-oss/Understudy#static-members) in the README, with the limits.
- ``FreshSpies`` and ``StaticSpies``.
