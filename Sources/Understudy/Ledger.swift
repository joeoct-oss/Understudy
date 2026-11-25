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
    /// A computed answer runs outside the lock, so it may call the spy again.
    func record(_ input: Input) -> Output {
        let answer = synchronized {
            recordedCalls.append(input)
            guard queuedAnswers.isEmpty else {
                return Answer.value(queuedAnswers.removeFirst())
            }
            return standingAnswer
        }
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
}

extension Ledger: @unchecked Sendable where Input: Sendable, Output: Sendable { }
