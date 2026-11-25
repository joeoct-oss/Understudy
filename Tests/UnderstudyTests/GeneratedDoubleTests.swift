//
//  GeneratedDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// Doubles written with `@GenerateSpies`: on a class in the test target, whose requirements have no
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
    func initAsksOnlyForAnswersWithNoObviousDefault() {
        let shop = SpyShop()

        let name = shop.name()
        let stock = shop.stock()
        let price = shop.price()
        let open = shop.isOpen
        let tags = shop.tags()
        let prices = shop.prices()
        let codes = shop.codes()

        let noTags: [String] = []
        let noPrices: [String: Double] = [:]
        let noCodes: Set<Int> = []
        #expect(name == "")
        #expect(stock == 0)
        #expect(price == 0)
        #expect(!open)
        #expect(tags == noTags)
        #expect(prices == noPrices)
        #expect(codes == noCodes)
    }

    @Test
    func initStillTakesEveryAnswerItTookBefore() {
        let shop = SpyShop(isOpen: true, name: "Corner", stock: 9, tags: ["new"])

        let expectedTags = ["new"]
        #expect(shop.name() == "Corner")
        #expect(shop.stock() == 9)
        #expect(shop.isOpen)
        #expect(shop.tags() == expectedTags)
    }

    @Test
    func staticSpyAnswersWhatTheTestScripts() {
        SpyStopwatch.elapsedSpy.willReturn(5)
        CalendarSpy.todaySpy.willReturn("Monday")

        let elapsed = SpyStopwatch.elapsed()
        SpyStopwatch.unit = "ms"
        let today = CalendarSpy.today()
        let zone = CalendarSpy.zone

        let expectedUnits = ["ms"]
        #expect(elapsed == 5)
        #expect(SpyStopwatch.elapsedSpy.callCount == 1)
        #expect(SpyStopwatch.unitSpy.sets == expectedUnits)
        #expect(today == "Monday")
        #expect(zone == "")
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
    func typedThrowsRequirementThrowsTheScriptedError() async {
        let auth = SpyAuth(signIn: "ana")
        let protocolAuth = AuthSpy(signIn: "ana")
        auth.signInSpy.willThrow(AuthError.wrongPassword)
        protocolAuth.signInSpy.willThrow(AuthError.wrongPassword)

        await #expect(throws: AuthError.wrongPassword) {
            try await auth.signIn(email: "ana@example.com")
        }
        await #expect(throws: AuthError.wrongPassword) {
            try await protocolAuth.signIn(email: "ana@example.com")
        }
    }

    @Test
    func typedThrowsRequirementReturnsTheScriptedAnswer() async throws {
        let auth = SpyAuth(signIn: "ana")
        let protocolAuth = AuthSpy(signIn: "bo")

        let account = try await auth.signIn(email: "ana@example.com")
        let protocolAccount = try await protocolAuth.signIn(email: "bo@example.com")
        auth.forget()
        try auth.refresh()

        let expectedEmails = ["ana@example.com"]
        #expect(account == "ana")
        #expect(protocolAccount == "bo")
        #expect(auth.signInSpy.calls == expectedEmails)
        #expect(auth.forgetSpy.callCount == 1)
        #expect(auth.refreshSpy.callCount == 1)
    }

    @Test
    func asyncRequirementCanBeHeldUntilTheTestResumesIt() async throws {
        let loader = SpyLoader(load: "scripted")
        let clock = ClockSpy(now: 0)
        let load = loader.loadSpy.holdNextCall()
        let sleep = clock.sleepSpy.holdNextCall()

        let loading = Task {
            try await loader.load(path: "a")
        }
        let sleeping = Task {
            await clock.sleep(for: 3)
        }
        let path = await load.arrived()
        let seconds = await sleep.arrived()
        load.resume(returning: "held")
        sleep.resume(returning: ())
        let data = try await loading.value
        await sleeping.value

        #expect(path == "a")
        #expect(seconds == 3)
        #expect(data == "held")
    }

    @Test
    func propertiesKeepEverySetAndAnswerGets() {
        var expired = false
        let session = SpySession(user: "ana", onExpire: { expired = true })

        session.token = "abc"
        session.token = nil
        let user = session.user
        session.onExpire()

        let expectedTokens: [String?] = ["abc", nil]
        #expect(session.tokenSpy.sets == expectedTokens)
        #expect(session.token == nil)
        #expect(user == "ana")
        #expect(session.userSpy.getCount == 1)
        #expect(expired)
    }

    @Test
    func spiedPropertyWithAValueStartsWithIt() {
        let session = SpyProfile()

        let user = session.user
        session.user = "bo"

        let expectedUsers = ["bo"]
        #expect(user == "ana")
        #expect(session.userSpy.sets == expectedUsers)
        #expect(session.user == "bo")
    }

    @Test
    func spiedPropertyWithAValueWorksInASendableClass() async {
        let account = SpyAccount()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    account.user = "user \(index)"
                }
            }
        }

        #expect(account.userSpy.sets.count == 10)
    }

    @Test
    func spiedPropertyWithAValueWorksInAnActor() async {
        let counter = SpyCounter()

        await counter.bump()

        let expectedCounts = [1]
        #expect(counter.countSpy.sets == expectedCounts)
        #expect(counter.countSpy.value == 1)
    }

    @Test
    func genericMethodsRecordTheirInputsAndAnswerAsTheCallerAsks() async throws {
        let cache = SpyCache(load: 7)
        cache.valueSpy.willReturn("cached")

        cache.store(42, for: "answer")
        let text: String? = cache.value(for: "name")
        let missing: Int? = cache.missing(for: "none")
        let number: Int = try await cache.load("count")

        #expect(cache.storeSpy.lastCall?.value as? Int == 42)
        #expect(cache.storeSpy.lastCall?.key == "answer")
        #expect(text == "cached")
        #expect(missing == nil)
        #expect(number == 7)
    }

    @Test
    func genericArrayParameterIsRecorded() {
        let bag = SpyBag(all: [], lookup: [:], unique: [])

        bag.put([1, 2], first: nil)
        bag.put(["a"], first: "b")

        let expectedNumbers = [1, 2]
        let expectedLetters = ["a"]
        #expect(bag.putSpy.calls.first?.items as? [Int] == expectedNumbers)
        #expect(bag.putSpy.lastCall?.items as? [String] == expectedLetters)
        #expect(bag.putSpy.lastCall?.first as? String == "b")
    }

    @Test
    func genericArrayAnswerComesBackTyped() {
        let bag = SpyBag(all: [3], lookup: ["a": 1], unique: [5])
        let protocolBag = ShelfSpy(all: ["x"])

        let items: [Int] = bag.all()
        let found: [String: Int] = bag.lookup(["b": 2])
        let unique: Set<Int> = bag.unique([5, 6])
        let shelved: [String] = protocolBag.all()

        let expectedItems = [3]
        let expectedFound = ["a": 1]
        let expectedUnique: Set = [5]
        let expectedShelved = ["x"]
        #expect(items == expectedItems)
        #expect(found == expectedFound)
        #expect(unique == expectedUnique)
        #expect(shelved == expectedShelved)
        #expect(bag.lookupSpy.lastCall?["b"] as? Int == 2)
        #expect(bag.uniqueSpy.lastCall == Set([5, 6]))
    }

    @Test
    func protocolGenericMethodGetsASpy() {
        let reader = ReaderSpy(read: 3.5)

        let value: Double = reader.read("ratio")

        let expectedKeys = ["ratio"]
        #expect(reader.readSpy.calls == expectedKeys)
        #expect(value == 3.5)
    }

    @Test
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

    @Test
    func actorProtocolGetsAnActorSpy() async {
        let ledger = LedgerSpy(total: 5)

        await ledger.add(3)
        let total = await ledger.total

        let expectedAmounts = [3]
        #expect(ledger.addSpy.calls == expectedAmounts)
        #expect(total == 5)
    }

    @Test
    func protocolPropertiesGetPropertySpies() {
        let settings = SettingsSpy(volume: 3)

        settings.volume = 5
        let theme = settings.theme

        let expectedVolumes = [5]
        #expect(settings.volumeSpy.sets == expectedVolumes)
        #expect(settings.volume == 5)
        #expect(theme == nil)
    }

    @Test
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

    @Test
    func closureAnswerIsTakenAtCreation() {
        let ran = Spy<Void, Void>()
        let factory = SpyHandlerFactory(
            makeHandler: { ran() },
            makeSendableHandler: { ran() },
            makeWrappedHandler: { ran() }
        )

        factory.makeHandler()()
        factory.makeSendableHandler()()
        factory.makeWrappedHandler()()

        #expect(factory.makeHandlerSpy.callCount == 1)
        #expect(ran.callCount == 3)
    }

    @Test
    func variadicAndOpaqueParametersAreRecorded() {
        let printer = SpyPrinter()

        printer.print("a", "b")
        printer.show(7)

        let expectedLines = [["a", "b"]]
        #expect(printer.printSpy.calls == expectedLines)
        #expect(printer.showSpy.lastCall as? Int == 7)
    }

    @Test
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
@GenerateSpies
private final class SpyCatalog: Catalog {
    @Spied func product(id: Int) -> String
    @Spied func search(for query: String, limit: Int) -> String?
    @Spied func refresh()
    @Spied func remove(id: Int)
    @Spied func remove(named name: String)
}

/// A shop whose every answer has an obvious first value.
private protocol Shop: AnyObject {
    var isOpen: Bool { get set }
    func name() -> String
    func stock() -> Int
    func price() -> Double
    func tags() -> [String]
    func prices() -> [String: Double]
    func codes() -> Set<Int>
}

/// A shop the test makes with no arguments, or with only the answers it cares about.
///
/// Conformances:
/// - `Shop`, so a test can pass it where a shop is expected.
@GenerateSpies
private final class SpyShop: Shop {
    @SpiedProperty var isOpen: Bool
    @Spied func name() -> String
    @Spied func stock() -> Int
    @Spied func price() -> Double
    @Spied func tags() -> [String]
    @Spied func prices() -> [String: Double]
    @Spied func codes() -> Set<Int>
}

/// Measures time for the whole app, through static members.
private protocol Stopwatch {
    static var unit: String { get set }
    static func elapsed() -> Int
    func lap()
}

/// A stopwatch whose static answers the test scripts.
///
/// Conformances:
/// - `Stopwatch`, so a test can pass its type where a stopwatch is expected.
@GenerateSpies
private final class SpyStopwatch: Stopwatch {
    @SpiedProperty static var unit: String = "s"
    @Spied static func elapsed() -> Int
    @Spied func lap()
}

/// Tells the day and the time zone, through static members.
@GenerateSpies
private protocol Calendar {
    static var zone: String { get set }
    static func today() -> String
}

/// Loads data that may not be there.
private protocol Loader {
    func load(path: String) async throws -> String
}

/// A loader whose answers the test scripts.
///
/// Conformances:
/// - `Loader`, so a test can pass it where a loader is expected.
@GenerateSpies
private final class SpyLoader: Loader {
    @Spied func load(path: String) async throws -> String
}

/// Why signing in failed.
///
/// Conformances:
/// - `Error`, so a sign-in can throw it.
/// - `Equatable`, so a test can check which error came out.
private enum AuthError: Error, Equatable {
    case wrongPassword
}

/// Signs a person in and out, throwing only `AuthError`.
@GenerateSpies
private protocol Auth {
    func signIn(email: String) async throws(AuthError) -> String
}

/// Signs a person in and out, with every way to write `throws`.
private protocol AuthService {
    func signIn(email: String) async throws(AuthError) -> String
    func refresh() throws(any Error)
    func forget() throws(Never)
}

/// An auth service whose answers and errors the test scripts.
///
/// Conformances:
/// - `AuthService`, so a test can pass it where an auth service is expected.
@GenerateSpies
private final class SpyAuth: AuthService {
    @Spied func signIn(email: String) async throws(AuthError) -> String
    @Spied func refresh() throws(any Error)
    @Spied func forget() throws(Never)
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

/// The signed-in session, as a feature reads and changes it.
private protocol Session: AnyObject {
    var token: String? { get set }
    var user: String { get }
    var onExpire: () -> Void { get }
}

/// A session whose values the test chose, and that keeps every token set.
///
/// Conformances:
/// - `Session`, so a test can pass it where a session is expected.
@GenerateSpies
private final class SpySession: Session {
    @SpiedProperty var token: String?
    @SpiedProperty var user: String
    @SpiedProperty var onExpire: () -> Void
}

/// A profile a screen shows and edits.
private protocol Profile: AnyObject {
    var user: String { get set }
}

/// A profile whose user starts as "ana", so the test makes it with no arguments.
///
/// Conformances:
/// - `Profile`, so a test can pass it where a profile is expected.
@GenerateSpies
private final class SpyProfile: Profile {
    @SpiedProperty var user: String = "ana"
}

/// Counts on its own actor.
private protocol Counter: Actor {
    var count: Int { get set }
}

/// A counter that starts at 0, an actor like the real one.
///
/// Conformances:
/// - `Counter`, so a test can pass it where a counter is expected.
@GenerateSpies
private actor SpyCounter: Counter {
    @SpiedProperty var count: Int = 0
    // Bumps the count from inside the actor, as the code under test would.
    func bump() {
        count += 1
    }
}

/// A signed-in account that any task may read.
private protocol Account: Sendable {
    var user: String { get set }
}

/// A sendable account whose user starts as "ana", which `@Recorded` can't spy on.
///
/// Conformances:
/// - `Account`, so a test can pass it where an account is expected.
/// - `Sendable`: it stores only its spies, which are `Sendable`.
@GenerateSpies
private final class SpyAccount: Account, Sendable {
    @SpiedProperty var user: String = "ana"
}

/// Keeps values of any type under keys.
private protocol Cache {
    func store<Value: Codable>(_ value: Value, for key: String)
    func value<Value: Decodable>(for key: String) -> Value?
    func missing<Value>(for key: String) -> Value?
    func load<Value: Sendable>(_ key: String) async throws -> Value
}

/// A cache whose answers the test chose, whatever type the caller asks for.
///
/// Conformances:
/// - `Cache`, so a test can pass it where a cache is expected.
@GenerateSpies
private final class SpyCache: Cache {
    @Spied func store<Value: Codable>(_ value: Value, for key: String)
    @Spied func value<Value: Decodable>(for key: String) -> Value?
    @Spied func missing<Value>(for key: String) -> Value?
    @Spied func load<Value: Sendable>(_ key: String) async throws -> Value
}

/// Holds items of any type, in arrays, dictionaries and sets.
private protocol Bag {
    func put<Item>(_ items: [Item], first: Item?)
    func all<Item: Codable>() -> [Item]
    func lookup<Item>(_ map: [String: Item]) -> [String: Item]
    func unique<Item: Hashable>(_ items: Set<Item>) -> Set<Item>
}

/// A bag whose answers the test chose, whatever item type the caller asks for.
///
/// Conformances:
/// - `Bag`, so a test can pass it where a bag is expected.
@GenerateSpies
private final class SpyBag: Bag {
    @Spied func put<Item>(_ items: [Item], first: Item?)
    @Spied func all<Item: Codable>() -> [Item]
    @Spied func lookup<Item>(_ map: [String: Item]) -> [String: Item]
    @Spied func unique<Item: Hashable>(_ items: Set<Item>) -> Set<Item>
}

/// Lists the items on a shelf, of any type.
@GenerateSpies
private protocol Shelf {
    func all<Item: Codable>() -> [Item]
}

/// Reads settings of any type.
@GenerateSpies
private protocol Reader {
    func read<Value: Decodable>(_ key: String) -> Value
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

/// Settings a screen reads and changes.
@GenerateSpies
private protocol Settings: AnyObject {
    var volume: Int { get set }
    var theme: String? { get }
}

/// Prints lines and shows values.
private protocol Printer {
    func print(_ lines: String...)
    func show(_ value: some Equatable)
}

/// A printer that keeps what it was given.
///
/// Conformances:
/// - `Printer`, so a test can pass it where a printer is expected.
@GenerateSpies
private final class SpyPrinter: Printer {
    @Spied func print(_ lines: String...)
    @Spied func show(_ value: some Equatable)
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

/// Makes the handler a screen runs when it is tapped.
private protocol HandlerFactory {
    func makeHandler() -> () -> Void
    func makeSendableHandler() -> @Sendable () -> Void
    func makeWrappedHandler() -> (() -> Void)
}

/// A handler factory that gives the closure the test chose.
///
/// Conformances:
/// - `HandlerFactory`, so a test can pass it where a factory is expected.
@GenerateSpies
private final class SpyHandlerFactory: HandlerFactory {
    @Spied func makeHandler() -> () -> Void
    @Spied func makeSendableHandler() -> @Sendable () -> Void
    @Spied func makeWrappedHandler() -> (() -> Void)
}

/// Tells the time and waits, so a test can control both.
@GenerateSpies
private protocol Clock {
    func now() -> Int
    func sleep(for seconds: Int) async
}

/// Receives events from any thread.
///
/// Conformances:
/// - `Sendable`, because any task may send an event.
@GenerateSpies
private protocol EventSink: Sendable {
    func send(_ event: String)
}
