//
//  AcceptedDoubles.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Every shape of double the macros must accept, one case per kind of requirement.
extension ExpansionTests {
    static let accepted: [Accepted] = [
        Accepted(
            name: "a protocol with associated types",
            source: """
                @GenerateSpies
                protocol Repository {
                    associatedtype Item: Equatable
                    associatedtype Key = String
                    func item(for key: Key) -> Item?
                }
                """
        ),
        Accepted(
            name: "a protocol that inherits two others",
            source: """
                @GenerateSpies
                protocol Child: Base, Named, Sendable {
                    func pong(_ value: String)
                }
                """
        ),
        Accepted(
            name: "a class whose only spied member is a @Recorded property",
            source: """
                @GenerateSpies
                final class SpySession: Session {
                    @Recorded var user = "ana"
                    @Understudy.Recorded var token = "abc"
                }
                """
        ),
        Accepted(
            name: "requirements with and without answers to give",
            source: """
                @GenerateSpies
                final class SpyCatalog: Catalog {
                    @Spied func product(id: Int) -> String
                    @Spied func search(for query: String, limit: Int) -> String?
                    @Spied func refresh()
                }
                """
        ),
        Accepted(
            name: "properties with and without values to give",
            source: """
                @GenerateSpies
                final class SpySession: Session {
                    @SpiedProperty var token: String?
                    @SpiedProperty var user: String
                    @SpiedProperty var onExpire: () -> Void
                    @SpiedProperty var name: String = "ana"
                    @Spied func token(for user: String) -> String
                }
                """
        ),
        Accepted(
            name: "overloads with different labels",
            source: """
                @GenerateSpies
                final class SpyCatalog: Catalog {
                    @Spied func remove(id: Int)
                    @Spied func remove(named name: String)
                }
                """
        ),
        Accepted(
            name: "throwing and async requirements",
            source: """
                @GenerateSpies
                final class SpyLoader: Loader {
                    @Spied func load(path: String) async throws -> String
                }
                """
        ),
        Accepted(
            name: "typed throws, including throws(any Error) and throws(Never)",
            source: """
                @GenerateSpies
                final class SpyAuth: Auth {
                    @Spied func signIn(email: String) async throws(AuthError) -> String
                    @Spied func signOut() throws(AuthError)
                    @Spied func token<Value: Decodable>(for key: String) throws(AuthError) -> Value
                    @Spied func refresh() throws(any Error)
                    @Spied func forget() throws(Never)
                }

                @GenerateSpies
                protocol Auth {
                    func signIn(email: String) async throws(AuthError) -> String
                    func forget() throws(Never)
                }
                """
        ),
        Accepted(
            name: "closures in and out, variadic and opaque parameters",
            source: """
                @GenerateSpies
                final class SpyFactory: Factory {
                    @Spied func make(then action: @escaping @Sendable () -> Void)
                    @Spied func handler() -> () -> Void
                    @Spied func sendableHandler() -> @Sendable () -> Void
                    @Spied func wrappedHandler() -> (() -> Void)
                    @Spied func sum(_ numbers: Int...) -> Int
                    @Spied func show(_ view: some View)
                }
                """
        ),
        Accepted(
            name: "isolated and nonisolated requirements of any access level",
            source: """
                @GenerateSpies
                @MainActor
                open class SpyGate: Gate {
                    @Spied nonisolated func isOpen() -> Bool
                    @Spied func open()
                }

                @GenerateSpies
                private final class SpyLog: Log {
                    @Spied func write(_ text: String)
                }
                """
        ),
        Accepted(
            name: "simple generic methods",
            source: """
                @GenerateSpies
                final class SpyCache: Cache {
                    @Spied func store<Value: Codable>(_ value: Value, for key: String)
                    @Spied func value<Value: Decodable>(for key: String) -> Value?
                    @Spied func load<Value>(_ key: String) async throws -> Value
                    @Spied func all<Value: Sendable & Codable>(_ values: Value...)
                }

                @GenerateSpies
                protocol Settings {
                    func read<Value: Decodable>(_ key: String) -> Value
                }
                """
        ),
        Accepted(
            name: "generics inside arrays, optionals, dictionary values and sets",
            source: """
                @GenerateSpies
                final class SpyBag: Bag {
                    @Spied func put<Item: Codable>(_ items: [Item], first: Item?)
                    @Spied func all<Item: Codable>() -> [Item]
                    @Spied func maybe<Item>() -> [Item]?
                    @Spied func lookup<Item>(_ map: [String: Item]) -> [String: Item]
                    @Spied func unique<Item: Hashable>(_ items: Set<Item>) -> Set<Item>
                }

                @GenerateSpies
                protocol Bag {
                    func all<Item: Codable>() -> [Item]
                }
                """
        ),
        Accepted(
            name: "subscripts with one or several indices, overloaded, and in protocols",
            source: """
                @GenerateSpies
                final class SpyGrid: Grid {
                    subscript(row: Int, column: Int) -> String { @Spied get {} @Spied set {} }
                    subscript(name: String) -> String? { @Spied get {} @Spied set {} }
                    subscript(_ index: Int) -> String { @Spied get {} @Spied set {} }
                }

                @GenerateSpies
                actor SpyShelf: Shelf {
                    subscript(index: Int) -> String { @Spied get {} @Spied set {} }
                }

                @GenerateSpies
                public protocol Table {
                    subscript(row: Int) -> String { get set }
                    subscript(key: String) -> Int? { get }
                }
                """
        ),
        Accepted(
            name: "static requirements and properties, on classes, actors and protocols",
            source: """
                @GenerateSpies
                public final class SpyClock: Clock {
                    @Spied static func now() -> Date?
                    @Spied class func ticks() -> Int
                    @SpiedProperty static var zone: String = "UTC"
                    @SpiedProperty static var offset: Int
                    @Spied func sleep(for seconds: Int) async
                }

                @GenerateSpies
                actor SpyTimer: Timer {
                    @Spied static func start() throws
                }

                @GenerateSpies
                protocol Calendar {
                    static var zone: String { get set }
                    static func today() -> String
                }
                """
        ),
        Accepted(
            name: "static requirements of standard types written with their module",
            source: """
                @GenerateSpies
                public final class SpyCounter: Counter {
                    @Spied static func total() -> Swift.Int
                    @SpiedProperty static var tags: Swift.Set<String>
                }

                @GenerateSpies
                protocol Limits {
                    static var maximum: Swift.Int { get }
                }
                """
        ),
        Accepted(
            name: "actors",
            source: """
                @GenerateSpies
                actor SpyStore: Store {
                    @Spied func save(_ item: String) async throws
                    @Spied nonisolated func name() -> String
                    @SpiedProperty var count: Int
                }

                @GenerateSpies
                protocol Ledger: Actor {
                    var total: Int { get }
                    func add(_ amount: Int)
                }
                """
        ),
        Accepted(
            name: "protocols you own",
            source: """
                @GenerateSpies
                @MainActor
                public protocol Clock: AnyObject {
                    var zone: String { get set }
                    var label: String? { get }
                    func now() -> Int
                    func sleep(for seconds: Int) async throws
                    func tick() async
                }

                @GenerateSpies
                fileprivate protocol EventSink: Sendable {
                    func send(_ event: String)
                }
                """
        ),
    ]
}
