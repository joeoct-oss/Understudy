//
//  IsolationDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How generated doubles of actors, main actor types and every access level behave once the
/// compiler builds them.
@Suite("Generated doubles of actors and isolated types")
struct IsolationDoubleTests {
    @Test("An actor double records calls and properties, read without await")
    func actorDoubleRecordsCallsAndPropertiesReadWithoutAwait() async throws {
        let store = SpyStore(count: 1, name: "main")

        try await store.save("apple")
        await store.setCount(2)
        let name = store.name()

        let expectedItems = ["apple"]
        let expectedCounts = [2]
        #expect(store.saveSpy.calls == expectedItems)
        #expect(store.countSpy.sets == expectedCounts)
        #expect(name == "main")
    }

    @Test("An actor protocol gets an actor spy that records and answers")
    func actorProtocolGetsAnActorSpy() async {
        let ledger = LedgerSpy(total: 5)

        await ledger.add(3)
        let total = await ledger.total

        let expectedAmounts = [3]
        #expect(ledger.addSpy.calls == expectedAmounts)
        #expect(total == 5)
    }

    @Test("A main actor double records values that aren't Sendable")
    @MainActor
    func mainActorDoubleRecordsValuesThatAreNotSendable() async {
        let gate = SpyGate(isOpen: true)
        let screen = Screen(title: "Cart")
        let ran = Spy<Void, Void>()

        gate.requireAccount(for: screen) {
            ran()
        }
        gate.requireAccountSpy.lastCall?.action()
        await gate.present(screen)

        #expect(gate.presentSpy.lastCall === screen)
        #expect(gate.isOpen())
        #expect(gate.requireAccountSpy.lastCall?.screen === screen)
        #expect(ran.callCount == 1)
    }

    @Test("Doubles of every access level and isolation build and record calls")
    @MainActor
    func doublesOfEveryAccessLevelAndIsolationBuildAndRecord() async {
        let gate = SpyOpenGate(isOpen: true)
        let adder = SpyAdder(sum: 6)
        let scheduler = SpyScheduler()
        let clock = PublicClockSpy(now: 1)
        let log = FileLogSpy()

        let open = gate.isOpen()
        let total = adder.sum(1, 2, 3)
        scheduler.schedule { @Sendable in }
        let now = clock.now()
        log.write("saved")

        let expectedNumbers = [[1, 2, 3]]
        let expectedLines = ["saved"]
        #expect(open)
        #expect(total == 6)
        #expect(adder.sumSpy.calls == expectedNumbers)
        #expect(scheduler.scheduleSpy.callCount == 1)
        #expect(now == 1)
        #expect(log.writeSpy.calls == expectedLines)
    }
}

/// Asks for an account before an action, on the main actor.
@MainActor
private protocol AccountGate: AnyObject {
    func requireAccount(for screen: Screen, then action: @escaping () -> Void)
    func isOpen() -> Bool
    func present(_ screen: Screen) async
}

/// A screen, a class that isn't `Sendable`.
private final class Screen {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// An account gate that keeps each request and runs nothing, so the test decides.
///
/// Conformances:
/// - `AccountGate`, so a test can pass it where a gate is expected.
@GenerateSpies
@MainActor
private final class SpyGate: AccountGate {
    @Spied func requireAccount(for screen: Screen, then action: @escaping () -> Void)
    @Spied func isOpen() -> Bool
    @Spied func present(_ screen: Screen) async
}

/// Saves items, one at a time, on its own actor.
private protocol Store: Actor {
    var count: Int { get set }
    func save(_ item: String) async throws
    nonisolated func name() -> String
}

/// A store whose saves the test checks, an actor like the real one.
///
/// Conformances:
/// - `Store`, so a test can pass it where a store is expected.
@GenerateSpies
private actor SpyStore: Store {
    @SpiedProperty var count: Int
    @Spied func save(_ item: String) async throws
    @Spied nonisolated func name() -> String
    // Sets the count from outside the actor, as a test needs to.
    func setCount(_ value: Int) {
        count = value
    }
}

/// Adds amounts to a running total, on its own actor.
@GenerateSpies
private protocol Ledger: Actor {
    var total: Int { get }
    func add(_ amount: Int)
}

/// A gate any thread may ask whether it is open, owned by the main actor.
@MainActor
public protocol OpenGate {
    nonisolated func isOpen() -> Bool
}

/// An open, main-actor gate whose answer the test chose.
///
/// Conformances:
/// - `OpenGate`, so a test can pass it where a gate is expected.
@GenerateSpies
@MainActor
open class SpyOpenGate: OpenGate {
    @Spied nonisolated public func isOpen() -> Bool
}

/// Adds any count of numbers.
public protocol Adder {
    func sum(_ numbers: Int...) -> Int
}

/// A public adder that keeps every list of numbers it was given.
///
/// Conformances:
/// - `Adder`, so a test can pass it where an adder is expected.
@GenerateSpies
public final class SpyAdder: Adder {
    @Spied public func sum(_ numbers: Int...) -> Int
}

/// Runs work later, on any thread.
private protocol Scheduler {
    func schedule(_ work: @escaping @Sendable () -> Void)
}

/// A scheduler that keeps the work and never runs it.
///
/// Conformances:
/// - `Scheduler`, so a test can pass it where a scheduler is expected.
@GenerateSpies
private final class SpyScheduler: Scheduler {
    @Spied func schedule(_ work: @escaping @Sendable () -> Void)
}

/// Tells the time, for code in other modules too.
@GenerateSpies
@MainActor
public protocol PublicClock: AnyObject {
    func now() -> Int
}

/// Writes lines to a file in this file only.
@GenerateSpies
fileprivate protocol FileLog {
    func write(_ line: String)
}
