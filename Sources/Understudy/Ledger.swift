//
//  Ledger.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// Keeps a spy's calls and answers under one lock, so a spy can be called from any thread.
///
/// The spies share it: `Spy` keeps plain answers, and `ThrowingSpy` keeps results.
///
/// Conformances:
/// - `@unchecked Sendable` when `Input` and `Output` are, because every stored value is read and
///   written only under `lock`.
final class Ledger<Input, Output> {
    /// How the ledger answers a call.
    enum Answer {
        /// The same value for every call.
        case value(Output)
        /// A value worked out from each call's input.
        case computed(@Sendable (Input) -> Output)
    }

    /// Guards every stored value below.
    private let lock = NSLock()

    /// Every input, oldest first. `var` because each call adds one; only ``record(_:)`` adds.
    private var recordedCalls: [Input] = []

    /// The answer for every call once the queue is empty. `var` because a test can replace it;
    /// only ``answerEveryCall(with:)`` changes it.
    private var standingAnswer: Answer

    /// One-off answers in front of the standing one, next first. `var` because each call takes
    /// one; only ``record(_:)`` and the two `answer…` functions change it.
    private var queuedAnswers: [Output] = []

    /// Runs on each later call, outside the lock, with the call's input: for ``CallOrder`` and
    /// for tasks waiting on a call. `var` because watchers come and go; only ``watch(_:)`` and the
    /// waiting code change it.
    private var watchers: [Int: (Input) -> Void] = [:]

    /// The key the next watcher gets. `var` because each watcher takes one.
    private var nextWatcherKey = 0

    /// How many calls ``nextCall(within:)`` has handed out, oldest first. `var` because each
    /// handed-out call moves it on.
    private var handedOut = 0

    /// Calls the test holds, next first: each takes one call's input and the answer the spy would
    /// have given, and gives the answer the call returns once the test resumes it. `var` because
    /// each held call takes one; only ``holdNextCall(_:)`` adds.
    private var holds: [Hold] = []

    /// What the test expects, in the order it said so. `var` because each expectation adds one.
    private var expectations: [Expectation] = []

    /// Whether the spy is strict: set once the test expects anything, even no calls at all.
    private var isStrict = false

    /// A held call: runs in the caller's isolation, takes the call's input and the answer the spy
    /// would have given, and gives the answer the call returns.
    typealias Hold = (isolated (any Actor)?, Input, Output) async -> Output

    /// One expectation: the calls it matches, how many it wants, and how a report names them.
    struct Expectation {
        /// Whether a call matches. A test's own closure comes in `@Sendable`; the equality check
        /// captures only the expected input, which is `Sendable` whenever the spy is.
        let matches: (Input) -> Bool
        let times: Int
        let description: String
    }

    /// Every input, oldest first.
    var calls: [Input] {
        synchronized {
            recordedCalls
        }
    }

    /// Creates a ledger with no calls that answers with `answer`.
    init(answer: Answer) {
        standingAnswer = answer
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

    /// Keeps the input, then gives the next queued answer, or else the standing one.
    ///
    /// A computed answer and the watchers run outside the lock, so they may call the spy again.
    func record(_ input: Input) -> Output {
        let (answer, watching) = synchronized {
            recordedCalls.append(input)
            return (nextAnswer(), Array(watchers.values))
        }
        watching.forEach { watch in
            watch(input)
        }
        return resolve(answer, for: input)
    }

    /// Keeps the input like ``record(_:)``, and when the test holds this call, waits until the
    /// test resumes it. Runs in the caller's isolation, so its input never leaves it.
    func recordHolding(_ input: Input, isolation: isolated (any Actor)? = #isolation) async -> Output {
        let (answer, watching, hold) = synchronized {
            recordedCalls.append(input)
            let hold = holds.isEmpty ? nil : holds.removeFirst()
            return (nextAnswer(), Array(watchers.values), hold)
        }
        watching.forEach { watch in
            watch(input)
        }
        let scripted = resolve(answer, for: input)
        guard let hold else {
            return scripted
        }
        return await hold(isolation, input, scripted)
    }

    /// The next queued answer, or else the standing one. Called under the lock.
    private func nextAnswer() -> Answer {
        guard queuedAnswers.isEmpty else {
            return Answer.value(queuedAnswers.removeFirst())
        }
        return standingAnswer
    }

    /// The output `answer` gives for `input`.
    private func resolve(_ answer: Answer, for input: Input) -> Output {
        switch answer {
        case .value(let output):
            return output
        case .computed(let compute):
            return compute(input)
        }
    }

    /// Answers every later call with `answer`, dropping any queued answers.
    func answerEveryCall(with answer: Answer) {
        synchronized {
            standingAnswer = answer
            queuedAnswers.removeAll()
        }
    }

    /// Answers the next calls with `answers`, once each and in order, replacing any queued ones.
    func answerNextCalls(with answers: [Output]) {
        synchronized {
            queuedAnswers = answers
        }
    }

    /// Holds the next async call not yet held, with `hold`.
    func holdNextCall(_ hold: @escaping Hold) {
        synchronized {
            holds.append(hold)
        }
    }

    /// Runs `watch` on every later call, and gives the key that stops it.
    @discardableResult
    func watch(_ watch: @escaping (Input) -> Void) -> Int {
        synchronized {
            let key = nextWatcherKey
            nextWatcherKey += 1
            watchers[key] = watch
            return key
        }
    }

    /// Forgets every call, what ``nextCall(within:)`` handed out, and every expectation, and keeps
    /// the answers, the held calls and the watchers.
    func reset() {
        synchronized {
            recordedCalls.removeAll()
            handedOut = 0
            expectations.removeAll()
            isStrict = false
        }
    }

    /// Adds an expectation, which makes the spy strict.
    func expect(_ expectation: Expectation) {
        synchronized {
            expectations.append(expectation)
            isStrict = true
        }
    }

    /// Makes the spy strict with no expectations, so any call is unexpected.
    func expectNoCalls() {
        synchronized {
            isStrict = true
        }
    }

    /// Every expectation not met and every call nobody expected, in words. Empty when the spy
    /// isn't strict.
    func problems() -> [String] {
        let snapshot: (calls: [Input], expected: [Expectation], strict: Bool) = synchronized {
            (recordedCalls, expectations, isStrict)
        }
        let calls = snapshot.calls
        let expected = snapshot.expected
        guard snapshot.strict else {
            return []
        }
        let missed: [String] = expected.compactMap { expectation -> String? in
            let count = calls.filter(expectation.matches).count
            guard count != expectation.times else {
                return nil
            }
            return "expected \(Self.times(expectation.times)) with \(expectation.description), "
                + "got \(Self.times(count))"
        }
        let unexpected: [String] = calls.filter { input in
            !expected.contains { $0.matches(input) }
        }.map { input in
            "unexpected call with \(String(describing: input))"
        }
        return missed + unexpected
    }

    /// "1 call" or "n calls".
    private static func times(_ count: Int) -> String {
        count == 1 ? "1 call" : "\(count) calls"
    }
}

extension Ledger where Input: Sendable {
    /// The oldest call not yet handed out, waiting up to `seconds` for one; `nil` when none
    /// comes in time.
    func nextCall(within seconds: Double) async -> Input? {
        let delivery = Delivery<Input>()
        let key: Int? = synchronized {
            if handedOut < recordedCalls.count {
                _ = delivery.deliver(recordedCalls[handedOut])
                handedOut += 1
                return nil
            }
            let key = nextWatcherKey
            nextWatcherKey += 1
            watchers[key] = { [unowned self] _ in
                self.handOutNext(to: delivery, key: key)
            }
            return key
        }
        if key != nil {
            delivery.expire(after: seconds)
        }
        return await delivery.value()
    }

    /// Hands the oldest call not yet handed out to `delivery` and stops watching, unless another
    /// wait took that call first. A call that comes after the wait's time is up stays for the
    /// next wait.
    private func handOutNext(to delivery: Delivery<Input>, key: Int) {
        synchronized {
            if handedOut < recordedCalls.count, watchers.removeValue(forKey: key) != nil,
               delivery.deliver(recordedCalls[handedOut]) {
                handedOut += 1
            }
        }
    }
}

extension Ledger: @unchecked Sendable where Input: Sendable, Output: Sendable { }
