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
/// Or watch them all at once, in a block:
///
/// ```swift
/// let order = CallOrder {
///     Watched(store.saveSpy, as: "save")
///     Watched(analytics.sendSpy, as: "send")
/// }
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

    /// Creates a call order that watches every spy in `watches`, as `watch(_:as:)` would.
    public convenience init(@CallOrderBuilder _ watches: () -> [Watched]) {
        self.init()
        for watch in watches() {
            watch(self)
        }
    }

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

/// One spy for a ``CallOrder`` to watch, under the name the test picks, in a
/// `CallOrder { ... }` block:
///
/// ```swift
/// let order = CallOrder {
///     Watched(store.saveSpy, as: "save")
/// }
/// ```
///
/// Named `Watched` rather than `Watch`, which an app's own types, such as a watchOS screen, often
/// use, so a test that imports both modules keeps compiling.
///
/// Not `Sendable`: it holds the spy, which is `Sendable` only when its input and output are. It
/// is made and used in one block.
public struct Watched {
    /// Starts watching the spy on the order it is given.
    private let start: (CallOrder) -> Void

    /// Watches `spy` under `name`.
    public init<Input, Output>(_ spy: Spy<Input, Output>, as name: String) {
        start = { order in
            order.watch(spy, as: name)
        }
    }

    /// Watches `spy` under `name`.
    public init<Input, Output>(_ spy: ThrowingSpy<Input, Output>, as name: String) {
        start = { order in
            order.watch(spy, as: name)
        }
    }

    /// Starts watching the spy on `order`, as `CallOrder.watch(_:as:)` would.
    public func callAsFunction(_ order: CallOrder) {
        start(order)
    }
}

/// Collects the ``Watched`` lines of a `CallOrder { ... }` block.
@resultBuilder
public enum CallOrderBuilder {
    /// The block's watches, in order.
    public static func buildBlock(_ watches: Watched...) -> [Watched] {
        watches
    }
}
