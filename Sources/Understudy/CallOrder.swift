//
//  CallOrder.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// Keeps the order of calls across several spies, under names the test picks, so a test can check
/// that one thing happened before another:
///
/// ```swift
/// let order = CallOrder()
/// order.watch(store.saveSpy, as: "save")
/// order.watch(analytics.sendSpy, as: "send")
///
/// await screen.submit()
///
/// #expect(order.names == ["save", "send"])
/// ```
///
/// It sees only calls made after it starts watching.
///
/// Conformances:
/// - `@unchecked Sendable`, because spies called from any task add to it; every stored value is
///   read and written under `lock`.
public final class CallOrder: @unchecked Sendable {
    /// Guards every stored value below.
    private let lock = NSLock()

    /// The name of each call, oldest first. `var` because each call adds one.
    private var recorded: [String] = []

    /// Creates an empty call order.
    public init() { }

    /// The name of each call to a watched spy, oldest first.
    public var names: [String] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recorded
    }

    /// Adds `name` for every later call to `spy`.
    public func watch<Input, Output>(_ spy: Spy<Input, Output>, as name: String) {
        spy.onEveryCall { [self] in
            add(name)
        }
    }

    /// Adds `name` for every later call to `spy`.
    public func watch<Input, Output>(_ spy: ThrowingSpy<Input, Output>, as name: String) {
        spy.onEveryCall { [self] in
            add(name)
        }
    }

    /// Adds one call's name.
    private func add(_ name: String) {
        lock.lock()
        recorded.append(name)
        lock.unlock()
    }
}
