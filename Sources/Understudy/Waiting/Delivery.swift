//
//  Delivery.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// One value settled at most once, and handed to every task that waits for it: either a value, or
/// `nil` once its time is up. Whichever comes first wins, and the other is ignored.
///
/// Conformances:
/// - `@unchecked Sendable`, because the task that waits and the code that delivers run anywhere;
///   every stored value is read and written under `lock`, and `Value` is `Sendable`.
final class Delivery<Value: Sendable>: @unchecked Sendable {
    /// Guards every stored value below.
    private let lock = NSLock()

    /// The outcome once there is one. `var` because it is set once, by the first of a delivery and
    /// the timeout.
    private var outcome: Value??

    /// The tasks waiting for the outcome. `var` because each task that waits adds itself, and the
    /// outcome takes them all.
    private var waiters: [CheckedContinuation<Value?, Never>] = []

    /// Delivers `value`, unless an outcome came first, and says whether it was delivered.
    func deliver(_ value: Value) -> Bool {
        settle(value)
    }

    /// Delivers `nil` after `seconds`, unless an outcome came first.
    func expire(after seconds: Double) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            settle(nil)
        }
    }

    /// The outcome, waiting for it if it hasn't come yet.
    func value() async -> Value? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(returning: outcome)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    /// Keeps the first outcome and wakes every waiting task, and says whether `value` was the
    /// first.
    @discardableResult
    private func settle(_ value: Value?) -> Bool {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return false
        }
        outcome = .some(value)
        let waiting = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in waiting {
            waiter.resume(returning: value)
        }
        return true
    }
}
