//
//  Recorded.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Spies on a property of a class, with its first value at the declaration: the value lives in a
/// ``PropertySpy``, which `$name` gives the test.
///
/// ```swift
/// final class SpySession: Session {
///     @Recorded var user = "ana"
/// }
///
/// session.user = "bo"
/// session.$user.sets          // ["bo"]
/// session.$user.willReturn("cy")
/// ```
///
/// It works in a class written by hand and in a ``GenerateSpies()`` class, next to
/// ``SpiedProperty()``. In an actor, use ``SpiedProperty()``: an actor's `$name` would need
/// `await`. A `Sendable` class can't hold it, because a wrapped property's storage is a `var`; use
/// ``SpiedProperty()`` with a first value, `@SpiedProperty var user: String = "ana"`.
///
/// Conformances:
/// - `Sendable` when `Value` is `Sendable`: it stores only its ``PropertySpy``, which is then
///   `Sendable` too.
@propertyWrapper
public struct Recorded<Value> {
    /// The spy that holds the value: `$name`.
    public let projectedValue: PropertySpy<Value>

    /// The property's value. A get is counted and a set is kept, as ``PropertySpy`` does.
    public var wrappedValue: Value {
        get {
            projectedValue.get()
        }
        nonmutating set {
            projectedValue.set(newValue)
        }
    }

    /// Spies on a property whose gets answer `wrappedValue` until a set or the test changes it.
    public init(wrappedValue: Value) {
        projectedValue = PropertySpy(returning: wrappedValue)
    }
}

extension Recorded: Sendable where Value: Sendable { }
