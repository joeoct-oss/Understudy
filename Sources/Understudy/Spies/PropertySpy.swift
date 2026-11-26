//
//  PropertySpy.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// Stands in for one property of a test double: answers every get with its value, counts the gets,
/// and keeps every value set, in order. A set changes what later gets answer, as a real property
/// would.
///
/// ```swift
/// final class SpySession: Session {
///     let tokenSpy = PropertySpy<String?>(returning: nil)
///
///     var token: String? {
///         get { tokenSpy.get() }
///         set { tokenSpy.set(newValue) }
///     }
/// }
/// ```
///
/// `@GenerateSpies` writes this for every `@Spied var`.
///
/// Conformances:
/// - `@unchecked Sendable` when `Value` is `Sendable`: every stored value is read and written under
///   `lock`.
public final class PropertySpy<Value> {
    /// Guards every stored value below.
    private let lock = NSLock()

    /// What gets answer. `var` because a set or ``willReturn(_:)`` changes it.
    private var current: Value

    /// How many gets so far. `var` because each get adds one.
    private var gets = 0

    /// Every value set, oldest first. `var` because each set adds one.
    private var setValues: [Value] = []

    /// Creates a property spy whose gets answer `value` until a set or the test changes it.
    public init(returning value: Value) {
        current = value
    }

    /// What gets answer now.
    public var value: Value {
        synchronized {
            current
        }
    }

    /// The number of gets so far.
    public var getCount: Int {
        synchronized {
            gets
        }
    }

    /// Every value set, oldest first.
    public var sets: [Value] {
        synchronized {
            setValues
        }
    }

    /// Answers later gets with `value`, without counting as a set.
    public func willReturn(_ value: Value) {
        synchronized {
            current = value
        }
    }

    /// Forgets every get and every set, so the test can check what happens next on its own. Keeps
    /// the value later gets answer.
    public func reset() {
        synchronized {
            gets = 0
            setValues.removeAll()
        }
    }

    /// Counts a get and answers it: what the property's getter calls.
    public func get() -> Value {
        synchronized {
            gets += 1
            return current
        }
    }

    /// Keeps `value` and answers later gets with it: what the property's setter calls.
    public func set(_ value: Value) {
        synchronized {
            setValues.append(value)
            current = value
        }
    }

    /// Runs `body` while holding the lock.
    private func synchronized<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}

extension PropertySpy: @unchecked Sendable where Value: Sendable { }
