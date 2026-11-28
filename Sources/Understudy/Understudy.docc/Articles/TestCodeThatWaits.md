# Test code that waits

Check what your code does while a call is in flight, wait for a call another task makes, and move time without waiting for it.

## Overview

Code that waits, for the network, for another task or for time to pass, is where tests turn slow or flaky. Understudy gives a test three ways to stay in charge: it can hold a call to an `async` requirement, wait for a call that another task makes, and move a ``TestClock`` instead of sleeping. Each runs at the speed of the code, with no real waiting.

### Hold a call

A spy for an `async` requirement can hold its next call. The test then checks what the screen shows while the call waits, and resumes it with the answer it chooses:

```swift
let refresh = feed.refreshSpy.holdNextCall()
let task = Task { await screen.reload() }

await refresh.arrived()
#expect(screen.isLoading)

refresh.resume(returning: ())
await task.value
#expect(!screen.isLoading)
```

`resume(throwing:)` fails the call instead, and `resumeWithScriptedAnswer()` gives the answer the spy was scripted with. Calls the test doesn't hold answer at once. See ``HeldCall``.

### Wait for a call

When the code under test calls a double from a task of its own, the test waits for that call instead of sleeping:

```swift
screen.startPolling()

let page = try #require(await feed.pageSpy.nextCall())
#expect(page == 1)
```

`nextCall()` gives each call once, in order, or `nil` when none comes in time: one second by default, or the time `within:` gives.

### Move time with a test clock

Code that sleeps, such as a retry delay, a debounce or a timeout, takes a clock, with the real one as its default:

```swift
final class Greeter: Sendable {
    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func greet(_ name: String) async throws -> String {
        try await clock.sleep(for: .milliseconds(400))
        return "Hello, \(name)"
    }
}
```

The test passes a ``TestClock`` and moves it, so no real time passes:

```swift
@Test("Greets after the delay", .timeLimit(.minutes(1)))
func greetsAfterTheDelay() async throws {
    let clock = TestClock()
    let greeter = Greeter(clock: clock)

    async let greeting = greeter.greet("ana")
    await clock.advance(by: .milliseconds(400))

    #expect(try await greeting == "Hello, ana")
}
```

The time limit turns a sleep the clock never wakes into a failure instead of a stalled run, and `async let` keeps the sleeping work inside the test, so the limit can cancel it.

## Where the rules live

- [Async calls](https://github.com/joeoct-oss/Understudy#async-calls) and [Test clock](https://github.com/joeoct-oss/Understudy#test-clock) in the README: what `advance` promises, and the clock's limits.
