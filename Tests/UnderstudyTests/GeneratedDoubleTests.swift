//
//  GeneratedDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// Doubles written with `@Understudy`: on a class in the test target, whose requirements have no
/// body, marked `@Spied`, and on a protocol, which gets a spy class next to it.
@Suite("Generated doubles")
struct GeneratedDoubleTests {
    /// The error the tests script.
    ///
    /// Conformances:
    /// - `Error`, so a generated spy can throw it.
    /// - `Equatable`, so a test can check which error came out.
    private enum LoadError: Error, Equatable {
        case offline
    }

    @Test
    func requirementRecordsItsInputAndGivesTheStandingAnswer() {
        let catalog = SpyCatalog(product: "apple")

        let name = catalog.product(id: 7)

        let expectedIDs = [7]
        #expect(name == "apple")
        #expect(catalog.productSpy.calls == expectedIDs)
    }

    @Test
    func optionalAndVoidAnswersNeedNothingAtCreation() {
        let catalog = SpyCatalog(product: "apple")

        let found = catalog.search(for: "pear", limit: 3)
        catalog.refresh()

        #expect(found == nil)
        #expect(catalog.searchSpy.lastCall?.query == "pear")
        #expect(catalog.searchSpy.lastCall?.limit == 3)
        #expect(catalog.refreshSpy.callCount == 1)
    }

    @Test
    func overloadsGetSpiesNamedWithTheirLabels() {
        let catalog = SpyCatalog(product: "apple")

        catalog.remove(id: 1)
        catalog.remove(named: "pear")

        let expectedIDs = [1]
        let expectedNames = ["pear"]
        #expect(catalog.removeIdSpy.calls == expectedIDs)
        #expect(catalog.removeNamedSpy.calls == expectedNames)
    }

    @Test
    func throwingAndAsyncRequirementsUseAThrowingSpy() async {
        let loader = SpyLoader(load: "data")
        loader.loadSpy.willThrow(LoadError.offline)

        await #expect(throws: LoadError.offline) {
            try await loader.load(path: "a")
        }
        let expectedPaths = ["a"]
        #expect(loader.loadSpy.calls == expectedPaths)
    }

    @Test
    @MainActor
    func mainActorDoubleRecordsValuesThatAreNotSendable() {
        let gate = SpyGate(isOpen: true)
        let ran = Spy<Void, Void>()

        gate.requireAccount(for: "checkout") {
            ran()
        }
        gate.requireAccountSpy.lastCall?.action()

        #expect(gate.isOpen())
        #expect(gate.requireAccountSpy.lastCall?.reason == "checkout")
        #expect(ran.callCount == 1)
    }

    @Test
    func closureAnswerIsTakenAtCreation() {
        let ran = Spy<Void, Void>()
        let factory = SpyHandlerFactory(makeHandler: { ran() })

        factory.makeHandler()()

        #expect(factory.makeHandlerSpy.callCount == 1)
        #expect(ran.callCount == 1)
    }

    @Test
    func protocolGetsASpyClassNextToIt() async {
        let clock = ClockSpy(now: 10)

        let first = clock.now()
        await clock.sleep(for: 2)

        let expectedDurations = [2]
        #expect(first == 10)
        #expect(clock.sleepSpy.calls == expectedDurations)
    }

    @Test
    func sendableProtocolGetsASendableSpy() async {
        let sink = EventSinkSpy()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    sink.send("event \(index)")
                }
            }
        }

        #expect(sink.sendSpy.callCount == 100)
    }
}

/// A product catalog, as an app's feature would take it.
private protocol Catalog {
    func product(id: Int) -> String
    func search(for query: String, limit: Int) -> String?
    func refresh()
    func remove(id: Int)
    func remove(named name: String)
}

/// A catalog whose every requirement the macro writes.
///
/// Conformances:
/// - `Catalog`, so a test can pass it where a catalog is expected.
@Understudy
private final class SpyCatalog: Catalog {
    @Spied func product(id: Int) -> String
    @Spied func search(for query: String, limit: Int) -> String?
    @Spied func refresh()
    @Spied func remove(id: Int)
    @Spied func remove(named name: String)
}

/// Loads data that may not be there.
private protocol Loader {
    func load(path: String) async throws -> String
}

/// A loader whose answers the test scripts.
///
/// Conformances:
/// - `Loader`, so a test can pass it where a loader is expected.
@Understudy
private final class SpyLoader: Loader {
    @Spied func load(path: String) async throws -> String
}

/// Asks for an account before an action, on the main actor.
@MainActor
private protocol AccountGate: AnyObject {
    func requireAccount(for reason: String, then action: @escaping () -> Void)
    func isOpen() -> Bool
}

/// An account gate that keeps each request and runs nothing, so the test decides.
///
/// Conformances:
/// - `AccountGate`, so a test can pass it where a gate is expected.
@Understudy
@MainActor
private final class SpyGate: AccountGate {
    @Spied func requireAccount(for reason: String, then action: @escaping () -> Void)
    @Spied func isOpen() -> Bool
}

/// Makes the handler a screen runs when it is tapped.
private protocol HandlerFactory {
    func makeHandler() -> () -> Void
}

/// A handler factory that gives the closure the test chose.
///
/// Conformances:
/// - `HandlerFactory`, so a test can pass it where a factory is expected.
@Understudy
private final class SpyHandlerFactory: HandlerFactory {
    @Spied func makeHandler() -> () -> Void
}

/// Tells the time and waits, so a test can control both.
@Understudy
private protocol Clock {
    func now() -> Int
    func sleep(for seconds: Int) async
}

/// Receives events from any thread.
///
/// Conformances:
/// - `Sendable`, because any task may send an event.
@Understudy
private protocol EventSink: Sendable {
    func send(_ event: String)
}
