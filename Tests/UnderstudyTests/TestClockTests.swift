//
//  TestClockTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// `TestClock` moves only when the test moves it, and wakes what waits on it in deadline order.
///
/// Every test has a time limit, so a sleep the clock fails to wake fails the run instead of
/// stalling it. The sleeping work runs in `async let` children, which the limit cancels.
@Suite("Test clock")
struct TestClockTests {
    // How many times the actor-hop test runs, one after another, so the runs measure the clock
    // rather than a thousand tests competing for threads: the release gate for `advance`.
    private static let hopRuns = 1_000

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("A sleep wakes only when the clock reaches its deadline", .timeLimit(.minutes(1)))
    func sleeperWakesOnlyAtItsDeadline() async throws {
        let clock = TestClock()
        let log = Spy<String, Void>()

        async let napped: Void = nap(on: clock, for: .seconds(5), logging: "woke", to: log)
        await clock.advance(by: .seconds(4))
        let wokeEarly = log.wasCalled
        await clock.advance(by: .seconds(1))
        try await napped

        let expected = ["woke"]
        #expect(!wokeEarly)
        #expect(log.calls == expected)
        #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "Sleeps wake in deadline order in one advance, a sleep that follows a sleep included",
        .timeLimit(.minutes(1))
    )
    func sleepersWakeInDeadlineOrder() async throws {
        let clock = TestClock()
        let log = Spy<String, Void>()

        async let first: Void = napTwice(on: clock, log: log)
        async let second: Void = nap(on: clock, for: .seconds(20), logging: "second", to: log)
        await clock.advance(by: .seconds(30))
        try await first
        try await second

        let expected = ["first, at 10", "second", "first, at 30"]
        #expect(log.calls == expected)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("A sleep until a deadline the clock has reached returns without an advance", .timeLimit(.minutes(1)))
    func sleepAlreadyDueReturnsAtOnce() async throws {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))

        try await clock.sleep(until: clock.now)
        try await clock.sleep(until: TestClock.Instant(offset: .seconds(3)))

        #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "A woken sleep reads its own deadline as the clock's time, not the end of the advance",
        .timeLimit(.minutes(1))
    )
    func nowIsTheDeadlineOfEachWokenSleeper() async throws {
        let clock = TestClock()
        let wokeAt = Spy<TestClock.Instant, Void>()

        async let early: Void = napThenReadTheTime(on: clock, for: .seconds(2), to: wokeAt)
        async let late: Void = napThenReadTheTime(on: clock, for: .seconds(7), to: wokeAt)
        await clock.advance(by: .seconds(10))
        try await early
        try await late

        let expected = [TestClock.Instant(offset: .seconds(2)), TestClock.Instant(offset: .seconds(7))]
        #expect(wokeAt.calls == expected)
        #expect(clock.now == TestClock.Instant(offset: .seconds(10)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "A cancelled sleep throws CancellationError, whether it was cancelled before or while it waited",
        .timeLimit(.minutes(1))
    )
    func cancelledSleeperThrowsCancellation() async {
        let clock = TestClock()

        let waiting = Task {
            try await clock.sleep(for: .seconds(1))
        }
        await clock.advance()
        waiting.cancel()
        let cancelledFirst = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            try await clock.sleep(for: .seconds(1))
        }

        await #expect(throws: CancellationError.self) {
            try await waiting.value
        }
        await #expect(throws: CancellationError.self) {
            try await cancelledFirst.value
        }
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("Running the clock finishes every sleep, and leaves it at the last deadline", .timeLimit(.minutes(1)))
    func runFinishesEveryWaitingSleep() async throws {
        let clock = TestClock()
        let log = Spy<String, Void>()

        async let looped: Void = napInALoop(on: clock, times: 5, to: log)
        await clock.run()
        try await looped

        #expect(log.callCount == 5)
        #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("Main-actor code that sleeps on the clock wakes inside the advance", .timeLimit(.minutes(1)))
    func mainActorSleeperWakes() async throws {
        let clock = TestClock()
        let log = Spy<String, Void>()

        async let napped: Void = napOnTheMainActor(on: clock, to: log)
        await clock.advance(by: .seconds(1))
        try await napped

        let expected = ["main actor"]
        #expect(log.calls == expected)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("The test clock goes where code asks for any clock, in place of the real one", .timeLimit(.minutes(1)))
    func clockIsUsableAsAnyClock() async throws {
        let clock = TestClock()
        let reminder = Reminder(clock: clock)

        async let message = reminder.remind(after: .seconds(60))
        await clock.advance(by: .seconds(60))

        #expect(try await message == Reminder.message)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "Woken work that hops across actors and the main actor between sleeps wakes at each deadline",
        .serialized,
        .timeLimit(.minutes(1)),
        arguments: 0..<hopRuns
    )
    func wokenWorkThatHopsAcrossActorsSettles(_ run: Int) async throws {
        let clock = TestClock()
        let wokeAt = Spy<TestClock.Instant, Void>()

        async let hopped: Void = napAndHop(on: clock, times: 3, to: wokeAt)
        await clock.advance(by: .seconds(3))
        try await hopped

        let expected = (1...3).map { TestClock.Instant(offset: .seconds($0)) }
        #expect(wokeAt.calls == expected)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "A woken task that sleeps again only after the advance returned still counts from when it woke",
        .timeLimit(.minutes(1))
    )
    func lateSleepCountsFromTheWakeDeadline() async throws {
        let clock = TestClock()
        let gate = Spy<Int, Void>()
        let held = gate.holdNextCall()
        let wokeAt = Spy<TestClock.Instant, Void>()

        async let napped: Void = napPastTheAdvance(on: clock, behind: gate, to: wokeAt)
        await clock.advance(by: .seconds(5))
        _ = await held.arrived()
        held.resume(returning: ())
        try await napped

        let expected = [TestClock.Instant(offset: .seconds(1)), TestClock.Instant(offset: .seconds(2))]
        #expect(wokeAt.calls == expected)
        #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test(
        "A sleep that another task starts during an advance is woken when its deadline falls inside it",
        .timeLimit(.minutes(1))
    )
    func sleepStartedDuringAdvanceIsWoken() async throws {
        let clock = TestClock()
        let wokeAt = Spy<TestClock.Instant, Void>()
        let (signals, signal) = AsyncStream.makeStream(of: Void.self)

        async let listened: Void = napOnSignal(on: clock, from: signals, to: wokeAt)
        async let signalled: Void = napThenSignal(on: clock, with: signal)
        await clock.advance(by: .seconds(5))
        let wokenInsideTheAdvance = wokeAt.calls
        try await signalled
        try await listened

        let expected = [TestClock.Instant(offset: .seconds(3))]
        #expect(wokenInsideTheAdvance == expected)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("Advancing to an instant in the past leaves the clock where it is", .timeLimit(.minutes(1)))
    func advanceToThePastDoesNothing() async {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))

        await clock.advance(to: TestClock.Instant(offset: .seconds(2)))

        #expect(clock.now == TestClock.Instant(offset: .seconds(5)))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("The clock moves by exactly what the test asks for, and instants measure it", .timeLimit(.minutes(1)))
    func clockMovesByExactlyWhatTheTestAsks() async {
        let clock = TestClock()
        let start = clock.now

        await clock.advance(by: .nanoseconds(1))

        #expect(clock.minimumResolution == .zero)
        #expect(start.duration(to: clock.now) == .nanoseconds(1))
    }
}

/// The code under test in the tests above: it waits on whatever clock it is given.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private struct Reminder {
    static let message = "Time's up"

    let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func remind(after delay: Duration) async throws -> String {
        try await clock.sleep(for: delay)
        return Self.message
    }
}

/// Hands out a value, so woken work has an actor to hop to.
private actor Inbox {
    func take() -> String {
        "letter"
    }
}

/// Keeps what it is given, so woken work has a second actor to hop to.
private actor Outbox {
    func send(_ letter: String) -> String {
        letter
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func nap(on clock: TestClock, for delay: Duration, logging name: String, to log: Spy<String, Void>)
    async throws
{
    try await clock.sleep(for: delay)
    log(name)
}

/// Sleeps until 10, then until 30, logging each wake.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napTwice(on clock: TestClock, log: Spy<String, Void>) async throws {
    try await nap(on: clock, for: .seconds(10), logging: "first, at 10", to: log)
    try await nap(on: clock, for: .seconds(20), logging: "first, at 30", to: log)
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napThenReadTheTime(on clock: TestClock, for delay: Duration, to wokeAt: Spy<TestClock.Instant, Void>)
    async throws
{
    try await clock.sleep(for: delay)
    wokeAt(clock.now)
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napInALoop(on clock: TestClock, times: Int, to log: Spy<String, Void>) async throws {
    for round in 1...times {
        try await nap(on: clock, for: .seconds(1), logging: "round \(round)", to: log)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
@MainActor
private func napOnTheMainActor(on clock: TestClock, to log: Spy<String, Void>) async throws {
    try await clock.sleep(for: .seconds(1))
    MainActor.assertIsolated()
    log("main actor")
}

/// Sleeps a second at a time, and after each wake hops to two actors and the main actor before
/// the next sleep.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napAndHop(on clock: TestClock, times: Int, to wokeAt: Spy<TestClock.Instant, Void>) async throws {
    let inbox = Inbox()
    let outbox = Outbox()
    for _ in 1...times {
        try await clock.sleep(for: .seconds(1))
        _ = await outbox.send(await inbox.take())
        await MainActor.run {
            wokeAt(clock.now)
        }
    }
}

/// Sleeps a second, then waits behind `gate`, which the test opens only after its advance has
/// returned, then sleeps another second.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napPastTheAdvance(
    on clock: TestClock,
    behind gate: Spy<Int, Void>,
    to wokeAt: Spy<TestClock.Instant, Void>
) async throws {
    try await napThenReadTheTime(on: clock, for: .seconds(1), to: wokeAt)
    await gate.respond(to: 1)
    try await napThenReadTheTime(on: clock, for: .seconds(1), to: wokeAt)
}

/// Sleeps until 1, then signals the listener, which the clock never woke.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napThenSignal(on clock: TestClock, with signal: AsyncStream<Void>.Continuation) async throws {
    try await clock.sleep(for: .seconds(1))
    signal.yield()
    signal.finish()
}

/// Waits for the signal, then sleeps two seconds on the clock.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func napOnSignal(
    on clock: TestClock,
    from signals: AsyncStream<Void>,
    to wokeAt: Spy<TestClock.Instant, Void>
) async throws {
    for await _ in signals {
        try await napThenReadTheTime(on: clock, for: .seconds(2), to: wokeAt)
    }
}
