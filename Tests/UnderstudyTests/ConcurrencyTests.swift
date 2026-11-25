//
//  ConcurrencyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// Spies work inside `Sendable` doubles called from many tasks, and inside main-actor doubles
/// that take values which aren't `Sendable`.
@Suite("Spies under Swift 6 concurrency")
struct ConcurrencyTests {
    /// How many tasks call at once.
    private static let callCount = 1_000

    @Test
    func concurrentCallsAreAllKept() async {
        let spy = Spy<Int, Void>()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<Self.callCount {
                group.addTask {
                    spy(index)
                }
            }
        }

        let expected = Set(0..<Self.callCount)
        #expect(spy.callCount == Self.callCount)
        #expect(Set(spy.calls) == expected)
    }

    @Test
    func sendableDoubleHoldsASpy() async {
        let sink = SpyEventSink()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<Self.callCount {
                group.addTask {
                    sink.send("event \(index)")
                }
            }
        }

        #expect(sink.sendCalls.callCount == Self.callCount)
    }

    @Test
    @MainActor
    func mainActorDoubleRecordsValuesThatAreNotSendable() {
        let gate = SpyGate()
        let screen = Screen(title: "Cart")
        let ran = Spy<Void, Void>()

        gate.requireAccount(for: screen) {
            ran()
        }
        gate.requireAccount.lastCall?.then()

        #expect(gate.requireAccount.lastCall?.screen === screen)
        #expect(ran.callCount == 1)
    }
}

/// Receives events from any thread.
///
/// Conformances:
/// - `Sendable`, because any task may send an event.
private protocol EventSink: Sendable {
    func send(_ event: String)
}

/// An event sink that keeps every event it was sent.
///
/// Conformances:
/// - `EventSink`, so a test can pass it where a sink is expected.
private final class SpyEventSink: EventSink {
    let sendCalls = Spy<String, Void>()

    func send(_ event: String) {
        sendCalls(event)
    }
}

/// A screen, a class that isn't `Sendable`.
private final class Screen {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// Asks for an account before an action, on the main actor.
@MainActor
private protocol AccountGate: AnyObject {
    func requireAccount(for screen: Screen, then action: @escaping () -> Void)
}

/// An account gate that keeps each request and runs nothing, so the test decides.
///
/// Conformances:
/// - `AccountGate`, so a test can pass it where a gate is expected.
@MainActor
private final class SpyGate: AccountGate {
    let requireAccount = Spy<(screen: Screen, then: () -> Void), Void>()

    func requireAccount(for screen: Screen, then action: @escaping () -> Void) {
        requireAccount((screen: screen, then: action))
    }
}
