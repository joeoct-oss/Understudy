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
/// deadline order, with `now` set to that deadline as it wakes. After each wake, it yields to
/// the other tasks many times, so the woken task runs on to its next sleep, even across actors,
/// and that sleep is woken in the same call when it falls inside the window. Swift has no public
/// way to know when every woken task has reached its next suspension, so this is a generous wait,
/// not a guarantee: a task that waits on something other than this clock between sleeps, such
/// as real I/O, may not be done when `advance` returns.
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

    /// A sleep that waits for the clock: when it wakes, and the task waiting on it.
    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// How many times ``advance(to:)`` yields after each wake, so woken work runs on to its next
    /// sleep. 64 left a task that hops across actors behind in tests; 1,000 never did, in
    /// milliseconds.
    private static let yieldsPerWake = 1_000

    /// Guards every stored value below.
    private let lock = NSLock()

    /// The clock's time. `var` because the clock moves; only ``takeSleeper(dueBy:)`` and
    /// ``moveNow(to:)`` move it, and never back.
    private var current = Instant(offset: .zero)

    /// The sleeps waiting for the clock, in the order they started. `var` because sleeps start
    /// and wake; only ``wait(_:until:with:)``, ``takeSleeper(dueBy:)`` and ``cancelSleeper(_:)``
    /// change it.
    private var sleepers: [Sleeper] = []

    /// The sleeps that have been called but don't wait yet. A sleep cancelled in that moment
    /// leaves it, and throws as soon as it would wait. `var` because sleeps start and get
    /// cancelled; only ``sleep(until:tolerance:)``, ``wait(_:until:with:)`` and
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
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                wait(id, until: deadline, with: continuation)
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
        await settle()
        while let sleeper = takeSleeper(dueBy: deadline) {
            sleeper.continuation.resume()
            await settle()
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
        await settle()
        while let sleeper = takeSleeper(dueBy: nil) {
            sleeper.continuation.resume()
            await settle()
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

    /// Yields to the other tasks, so work a wake started runs on to its next suspension.
    private func settle() async {
        for _ in 0..<Self.yieldsPerWake {
            await Task.yield()
        }
    }

    /// Keeps sleep `id` waiting for `deadline`, or ends it at once when the clock is already
    /// there or the sleep was cancelled first. A task cancelled before it sleeps lands here
    /// cancelled, because its cancellation handler runs first.
    private func wait(_ id: Int, until deadline: Instant, with continuation: CheckedContinuation<Void, any Error>) {
        let outcome: Result<Void, any Error>? = synchronized {
            if starting.remove(id) == nil {
                return .failure(CancellationError())
            }
            if deadline <= current {
                return .success(())
            }
            sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
            return nil
        }
        if let outcome {
            continuation.resume(with: outcome)
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
