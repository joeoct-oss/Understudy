//
//  TestClock.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// A clock that moves only when the test moves it, so code that waits can be tested without real
/// time passing.
///
/// The code under test takes a clock, with the real one as its default, and the test passes a
/// `TestClock` and moves it:
///
/// ```swift
/// let clock = TestClock()
/// let auth = AuthService(clock: clock)
/// async let account = auth.signIn(email: "ana@example.com", password: "pw")
///
/// await clock.advance(by: .milliseconds(400))
/// #expect(try await account.email == "ana@example.com")
/// ```
///
/// `now` starts at zero, and the clock never goes back. A sleep wakes only when ``advance(by:)``,
/// ``advance(to:)`` or ``run()`` reaches its deadline, and a cancelled sleep throws
/// `CancellationError`, as the system clocks do.
///
/// **What `advance` promises.** It wakes each sleep whose deadline the window reaches, in
/// deadline order, with `now` set to that deadline as it wakes. After each wake, it lets the
/// other tasks run until the woken task sleeps on the clock again, even across actors and the
/// main actor, and that sleep is woken in the same call when it falls inside the window. When
/// the woken task doesn't sleep again, and before the first wake, it lets them run for about
/// 10 ms of real time, so tasks just started reach their first sleep. Swift has no public way to
/// know when every task has reached its next suspension, so this is a generous wait, not a
/// guarantee: a task that waits on something other than this clock, such as real I/O, may not
/// be done when `advance` returns.
///
/// Conformances:
/// - `Clock`, so it goes wherever the code under test asks for an `any Clock<Duration>`.
/// - `@unchecked Sendable`, which `Clock` needs, so the test and the code under test can share
///   it across tasks and actors: every stored value is read and written only under `lock`.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public final class TestClock: Clock, @unchecked Sendable {
    /// A point in the test clock's time: how far it is from zero.
    ///
    /// Conformances:
    /// - `InstantProtocol`, which `Clock` needs for its instants: instants compare, hash and
    ///   move by a `Duration`.
    public struct Instant: InstantProtocol {
        /// How far this instant is from the clock's zero.
        public let offset: Duration

        /// Creates the instant `offset` from the clock's zero.
        public init(offset: Duration) {
            self.offset = offset
        }

        /// Whether `lhs` comes before `rhs`.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }

        /// The instant `duration` after this one.
        public func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        /// How long it is from this instant to `other`.
        public func duration(to other: Self) -> Duration {
            other.offset - offset
        }
    }

    /// A sleep that waits for the clock: when it wakes, the task that sleeps, and the
    /// continuation that resumes it.
    private struct Sleeper {
        let id: Int
        let deadline: Instant
        /// The sleeping task's identity, so ``settle(after:)`` sees when it sleeps again.
        let task: Int?
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// The fewest times ``advance(to:)`` yields after each wake, so woken work runs on to its
    /// next sleep. 64 left a task that hops across actors behind in tests.
    private static let minimumYields = 1_000

    /// How long ``advance(to:)`` keeps yielding after a wake when the woken task doesn't sleep
    /// again, and before its first wake, in real time. 1,000 yields alone, about a millisecond,
    /// left one run in 1,000 behind on a busy two-core machine, where a hop to the main actor
    /// can wait longer than that.
    private static let quietTime = Duration.milliseconds(10)

    /// Guards every stored value below.
    private let lock = NSLock()

    /// The clock's time. `var` because the clock moves; only ``takeSleeper(dueBy:)`` and
    /// ``moveNow(to:)`` move it, and never back.
    private var current = Instant(offset: .zero)

    /// The sleeps waiting for the clock, in the order they started. `var` because sleeps start
    /// and wake; only ``wait(_:)``, ``takeSleeper(dueBy:)`` and ``cancelSleeper(_:)``
    /// change it.
    private var sleepers: [Sleeper] = []

    /// The sleeps that have been called but don't wait yet. A sleep cancelled in that moment
    /// leaves it, and throws as soon as it would wait. `var` because sleeps start and get
    /// cancelled; only ``sleep(until:tolerance:)``, ``wait(_:)`` and
    /// ``cancelSleeper(_:)`` change it.
    private var starting: Set<Int> = []

    /// The id the next sleep gets. `var` because each sleep takes one.
    private var nextSleeperID = 0

    /// The clock's time, which starts at zero and moves only when the test moves it.
    public var now: Instant {
        synchronized {
            current
        }
    }

    /// Zero: the clock moves by exactly what the test asks for.
    public var minimumResolution: Duration {
        .zero
    }

    /// Creates a clock at zero, with nothing waiting.
    public init() { }

    /// Waits until the test moves the clock to `deadline`, or returns at once when it is already
    /// there. `tolerance` is ignored: the clock wakes a sleep exactly at its deadline.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before or while it waits.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = synchronized {
            let id = nextSleeperID
            nextSleeperID += 1
            starting.insert(id)
            return id
        }
        let task = withUnsafeCurrentTask { $0?.hashValue }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                wait(Sleeper(id: id, deadline: deadline, task: task, continuation: continuation))
            }
        } onCancel: {
            cancelSleeper(id)
        }
    }

    /// Moves the clock on by `duration`, waking every sleep it reaches, in deadline order. See
    /// the type's documentation for what it promises about the work each wake starts.
    public func advance(by duration: Duration) async {
        await advance(to: now.advanced(by: duration))
    }

    /// Moves the clock to `deadline`, waking every sleep it reaches, in deadline order, with
    /// ``now`` set to each sleep's deadline as it wakes. An instant before ``now`` moves nothing,
    /// because the clock never goes back.
    public func advance(to deadline: Instant) async {
        await settle(after: nil)
        while let sleeper = takeSleeper(dueBy: deadline) {
            sleeper.continuation.resume()
            await settle(after: sleeper)
        }
    }

    /// Lets work that is ready run, without moving the clock: a task just started reaches its
    /// first sleep, and a sleep already due wakes.
    public func advance() async {
        await advance(by: .zero)
    }

    /// Moves the clock on until nothing waits for it, waking each sleep at its deadline, so a
    /// loop of sleeps runs to its end. ``now`` is then the last deadline. Code that always
    /// starts another sleep, such as a repeating timer, keeps it running.
    public func run() async {
        await settle(after: nil)
        while let sleeper = takeSleeper(dueBy: nil) {
            sleeper.continuation.resume()
            await settle(after: sleeper)
        }
    }

    /// Runs `body` while holding the lock.
    ///
    /// Not `NSLock.withLock`, which Apple platforms have only from iOS 17 and macOS 14.
    private func synchronized<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }

    /// Yields to the other tasks, so the work `woken` started runs on to its next suspension:
    /// at least ``minimumYields`` times, then until the woken task sleeps on this clock again,
    /// or until ``quietTime`` has passed. With nothing woken yet, it waits the quiet time, so
    /// tasks just started reach their first sleep.
    private func settle(after woken: Sleeper?) async {
        let start = ContinuousClock.now
        for _ in 0..<Self.minimumYields {
            await Task.yield()
        }
        while ContinuousClock.now - start < Self.quietTime, !isSleeping(woken?.task) {
            await Task.yield()
        }
    }

    /// Whether `task` waits on this clock; `false` for no task.
    private func isSleeping(_ task: Int?) -> Bool {
        synchronized {
            task != nil && sleepers.contains { $0.task == task }
        }
    }

    /// Keeps `sleeper` waiting for its deadline, or ends it at once when the clock is already
    /// there or the sleep was cancelled first. A task cancelled before it sleeps lands here
    /// cancelled, because its cancellation handler runs first.
    private func wait(_ sleeper: Sleeper) {
        let outcome: Result<Void, any Error>? = synchronized {
            if starting.remove(sleeper.id) == nil {
                return .failure(CancellationError())
            }
            if sleeper.deadline <= current {
                return .success(())
            }
            sleepers.append(sleeper)
            return nil
        }
        if let outcome {
            sleeper.continuation.resume(with: outcome)
        }
    }

    /// Takes the sleep with the earliest deadline, the first started among equals, and moves the
    /// clock to its deadline. Only deadlines up to `limit` count; `nil` counts every one.
    ///
    /// When none is due, the clock moves to `limit` in the same step, so a sleep that starts
    /// afterwards inside the window finds its deadline reached and returns at once.
    private func takeSleeper(dueBy limit: Instant?) -> Sleeper? {
        synchronized {
            let due = sleepers.indices.filter { index in
                limit.map { sleepers[index].deadline <= $0 } ?? true
            }
            guard let next = due.min(by: { sleepers[$0].deadline < sleepers[$1].deadline }) else {
                if let limit {
                    moveNow(to: limit)
                }
                return nil
            }
            let sleeper = sleepers.remove(at: next)
            moveNow(to: sleeper.deadline)
            return sleeper
        }
    }

    /// Moves the clock to `instant`, unless that would take it back. Called under the lock.
    private func moveNow(to instant: Instant) {
        current = max(current, instant)
    }

    /// Ends sleep `id` with `CancellationError` when it waits, or makes it throw as soon as it
    /// would wait when it doesn't yet. A sleep that already woke is left as it is.
    private func cancelSleeper(_ id: Int) {
        let cancelled: Sleeper? = synchronized {
            starting.remove(id)
            return sleepers.firstIndex { $0.id == id }.map { sleepers.remove(at: $0) }
        }
        cancelled?.continuation.resume(throwing: CancellationError())
    }
}
