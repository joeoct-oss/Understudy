//
//  ExpansionTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
import UnderstudyMacros

/// What a person writing a double sees from the macros: every requirement they can write is
/// accepted and given a body, and every one they can't is refused at that requirement, with what to
/// do instead. How the generated doubles behave is tested where the compiler builds them, in
/// `GeneratedDoubleTests`.
@Suite("Macros accept what they can write and explain what they can't")
struct ExpansionTests {
    /// A double the macros must accept.
    struct Accepted: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String

        var testDescription: String {
            name
        }
    }

    /// A double the macros must refuse, with the message and where it points: the requirement, not
    /// the attribute, whenever there is one.
    struct Refused: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let message: String
        let line: Int
        let column: Int

        var testDescription: String {
            name
        }
    }

    @Test("GenerateSpies accepts every requirement it can write", arguments: accepted)
    func acceptsEveryRequirementItCanWrite(_ double: Accepted) {
        let (expanded, diagnostics) = expand(double.source)

        #expect(diagnostics.isEmpty)
        #expect(!expanded.hasError)
        #expect(!expanded.description.contains(Self.refusedBody))
    }

    /// A generic answer of the wrong type can't be tested by calling it, because it stops the
    /// process. What the person sees is this message, so the test checks the double says it.
    @Test("A generic answer of the wrong type stops with the spy's name and both types")
    func genericAnswerOfTheWrongTypeStopsWithTheSpyAndBothTypes() {
        let (expanded, _) = expand("""
            @GenerateSpies
            final class SpyCache: Cache {
                @Spied func value<Value: Decodable>(for key: String) -> Value
            }
            """)

        let message = #"@GenerateSpies: valueSpy answered \(type(of: __understudy_answer)), not \(Value.self)"#
        #expect(expanded.description.contains(message))
    }

    /// An error of another type than a typed `throws` names stops the process too, so the test
    /// checks the double says which spy threw it, and both types.
    @Test("A typed throws error of another type stops with the spy's name and both types")
    func typedThrowsWithAnotherErrorTypeStopsNamingTheSpy() {
        let (expanded, _) = expand("""
            @GenerateSpies
            final class SpyAuth: Auth {
                @Spied func signIn(email: String) async throws(AuthError) -> String
            }
            """)

        let message = #"@GenerateSpies: signInSpy threw \(type(of: error)), not \(AuthError.self)"#
        #expect(expanded.description.contains(message))
    }

    /// A get-only subscript of a protocol has no setter, so its spy class gets no set spy.
    @Test("A get-only subscript gets no set spy")
    func getOnlySubscriptHasNoSetSpy() {
        let (expanded, diagnostics) = expand("""
            @GenerateSpies
            protocol Table {
                subscript(row: Int) -> String { get }
            }
            """)

        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("subscriptSpy"))
        #expect(!expanded.description.contains("subscriptSetSpy"))
    }

    /// A type with no obvious value stays a required argument of the initializer, so the compiler
    /// still asks for it; the test checks the initializer the double declares.
    @Test("The initializer asks for a type with no obvious default and defaults the rest")
    func initStillAsksForATypeWithNoObviousDefault() {
        let (expanded, _) = expand("""
            @GenerateSpies
            final class SpyCatalog: Catalog {
                @Spied func product(id: Int) -> Product
                @Spied func count() -> Swift.Int
                @Spied func handler() -> () -> Void
                @Spied func list() -> Array<Int>
                @Spied func map() -> Dictionary<String, Int>
                @Spied func name() -> String
            }
            """)

        let initializer = "init(product: Product, count: Swift.Int, handler: @escaping () -> Void, "
            + #"list: Array<Int> = [], map: Dictionary<String, Int> = [:], name: String = "")"#
        #expect(expanded.description.contains(initializer))
    }

    /// The body `@Spied` writes for a requirement `@GenerateSpies` refused.
    private static let refusedBody = "@GenerateSpies can't write this requirement"

    @Test("GenerateSpies refuses what it can't write, at the requirement", arguments: refused)
    func refusesWhatItCannotWriteAtTheRequirement(_ double: Refused) {
        let (_, diagnostics) = expand(double.source)

        let expected = [
            "\(double.line):\(double.column): understudy.error: @GenerateSpies: \(double.message)",
        ]
        #expect(diagnostics == expected)
    }

    /// Expands the macros in `source`, and gives the expanded file and each diagnostic as
    /// "line:column: source: message".
    private func expand(_ source: String) -> (Syntax, [String]) {
        let file = Parser.parse(source: source)
        let context = BasicMacroExpansionContext(
            sourceFiles: [file: .init(moduleName: "TestModule", fullFilePath: "test.swift")]
        )
        let expanded = file.expand(
            macroSpecs: Self.macros,
            contextGenerator: { syntax in
                BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
            },
            indentationWidth: .spaces(4)
        )
        let diagnostics = context.diagnostics.map { diagnostic in
            let location = context.location(
                for: diagnostic.position,
                anchoredAt: diagnostic.node,
                fileName: "test.swift"
            )
            let source = diagnostic.diagnosticID == Self.understudyError ? "understudy.error" : "other"
            return "\(location.line):\(location.column): \(source): \(diagnostic.message)"
        }
        return (expanded, diagnostics)
    }

    /// The identifier of every error Understudy reports, so tools can tell its errors apart.
    private static let understudyError = MessageID(domain: "Understudy", id: "error")

    private static let macros: [String: MacroSpec] = [
        "GenerateSpies": MacroSpec(type: GenerateSpiesMacro.self),
        "Spied": MacroSpec(type: SpiedMacro.self),
        "SpiedProperty": MacroSpec(type: SpiedPropertyMacro.self),
    ]

    static let accepted: [Accepted] = [
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

    static let refused: [Refused] = [
        refusedRequirement("a generic with a where clause", "func load<Value>(_ key: String) -> Value where Value: Codable",
                           "'load' has a where clause; write its double by hand", column: 17),
        refusedRequirement("a generic parameter pack", "func load<each Value>(_ keys: repeat each Value)",
                           "'load' takes a parameter pack; write its double by hand", column: 17),
        refusedRequirement("a generic inside a closure", "func save<Value>(_ handler: (Value) -> Void)",
                           "'save' uses 'Value' inside another type; write its double by hand", column: 40),
        refusedRequirement("a generic inside a tuple", "func pair<Value>(_ both: (Value, Value))",
                           "'pair' uses 'Value' inside another type; write its double by hand", column: 37),
        refusedRequirement("a generic dictionary key", "func index<Key: Hashable>(_ map: [Key: Int])",
                           "'index' uses 'Key' inside another type; write its double by hand", column: 45),
        refusedRequirement("a generic inside another generic type", "func load<Value>(_ key: String) -> Result<Value, Error>",
                           "'load' uses 'Value' inside another type; write its double by hand", column: 47),
        refusedRequirement("a static requirement", "static func shared() -> Int",
                           "'shared' is static; write its double by hand", column: 24),
        refusedRequirement("a mutating requirement", "mutating func reset()",
                           "'reset' is mutating; @GenerateSpies writes classes and actors", column: 26),
        refusedRequirement("a typed throws of a generic parameter", "func load<Failure: Error>() throws(Failure)",
                           "'load' throws its generic parameter 'Failure'; write its double by hand", column: 47),
        refusedRequirement("rethrows", "func each(_ body: () throws -> Void) rethrows",
                           "'each' rethrows; write its double by hand", column: 17),
        refusedRequirement("a parameter with no name", "func move(_: Int)",
                           "'move' has a parameter with no name; name it", column: 22),
        refusedRequirement("an opaque answer", "func body() -> some View",
                           "'body' returns an opaque type; write its double by hand", column: 17),
        refusedRequirement("an inout parameter", "func bump(_ value: inout Int)",
                           "'bump' takes an inout parameter; write its double by hand", column: 22),
        refusedRequirement("an autoclosure", "func log(_ text: @autoclosure () -> String)",
                           "'log' takes an autoclosure; write its double by hand", column: 21),
        refusedProperty("a let", "let token: String",
                        "'token' is a let; declare it as a var", column: 24),
        refusedProperty("a property with accessors", "var token: String { \"\" }",
                        "'token' is @SpiedProperty, so give it no accessors", column: 24),
        refusedProperty("a static property", "static var shared: Int",
                        "'shared' is static; write its double by hand", column: 31),
        refusedProperty("a property with no type", "var token",
                        "'token' has no type; write its type", column: 24),
        refusedProperty("a tuple of properties", "var (first, second): (Int, Int)",
                        "declare one property at a time", column: 24),
        Refused(
            name: "overloads that differ only in their types",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String)
                    @Spied func write(_ number: Int)
                }
                """,
            message: "two requirements would both be spied on as 'writeSpy'; rename one",
            line: 4,
            column: 17
        ),
        Refused(
            name: "a requirement with a body",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String) {}
                }
                """,
            message: "'write' is @Spied, so give it no body",
            line: 3,
            column: 17
        ),
        Refused(
            name: "a class with nothing spied",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "mark each function to stand in for with @Spied and give it no body, "
                + "each property with @SpiedProperty or @Recorded, and the get and set of each subscript with @Spied",
            line: 1,
            column: 1
        ),
        Refused(
            name: "@Recorded in an actor",
            source: """
                @GenerateSpies
                actor SpyStore: Store {
                    @Recorded var count = 0
                    @Spied func save(_ item: String) async throws
                }
                """,
            message: "'count' is @Recorded, whose spy a test can't read on an actor without await; "
                + "use @SpiedProperty",
            line: 3,
            column: 19
        ),
        Refused(
            name: "a struct",
            source: """
                @GenerateSpies
                struct SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "attach it to a class, an actor or a protocol",
            line: 1,
            column: 1
        ),
        Refused(
            name: "@Spied outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@SpiedProperty outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    @SpiedProperty var token: String?
                }
                """,
            message: "@SpiedProperty needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@SpiedProperty on a subscript",
            source: """
                final class Lines {
                    @SpiedProperty subscript(line: Int) -> String { "" }
                }
                """,
            message: "@SpiedProperty goes on a var",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied in a struct",
            source: """
                struct Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied on something that isn't a function",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String)
                    @Spied init() {}
                }
                """,
            message: "@Spied goes on a function, or on the get and set of a subscript",
            line: 4,
            column: 5
        ),
        Refused(
            name: "a protocol initializer",
            source: """
                @GenerateSpies
                protocol Session {
                    init(user: String)
                }
                """,
            message: "'Session' has a requirement that is not a function, a property or a subscript; "
                + "write its double by hand, or use @GenerateSpies on a class or an actor",
            line: 3,
            column: 5
        ),
        Refused(
            name: "a protocol subscript that throws",
            source: """
                @GenerateSpies
                protocol Session {
                    subscript(key: String) -> String { get throws }
                }
                """,
            message: "'subscript' is async or throws; write its double by hand",
            line: 3,
            column: 5
        ),
        refusedRequirement("a static subscript", "static subscript(index: Int) -> Int { @Spied get {} }",
                           "'subscript' is static; write its double by hand", column: 12, marker: ""),
        refusedRequirement("a generic subscript", "subscript<Value>(key: String) -> Value { @Spied get {} }",
                           "'subscript' is generic; write its double by hand", column: 5, marker: ""),
        refusedRequirement("a subscript with a body", "subscript(index: Int) -> Int { @Spied get { 0 } }",
                           "'subscript' has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                               + "or { @Spied get {} } with no set", column: 5, marker: ""),
        refusedRequirement("an unmarked accessor", "subscript(index: Int) -> Int { @Spied get {} set {} }",
                           "'subscript' has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                               + "or { @Spied get {} } with no set", column: 5, marker: ""),
        refusedRequirement("a subscript index with no name", "subscript(_: Int) -> Int { @Spied get {} }",
                           "'subscript' has an index with no name; name it", column: 15, marker: ""),
        refusedRequirement("an inout subscript index", "subscript(index: inout Int) -> Int { @Spied get {} }",
                           "'subscript' takes an inout parameter; write its double by hand", column: 15, marker: ""),
        Refused(
            name: "a @Spied subscript outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    subscript(index: Int) -> Int { @Spied get {} }
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 36
        ),
        Refused(
            name: "@Spied on the get of a property",
            source: """
                @GenerateSpies
                final class Lines {
                    @Spied func clear()
                    var count: Int { @Spied get {} }
                }
                """,
            message: "@Spied goes on a function, or on the get and set of a subscript",
            line: 4,
            column: 22
        ),
        Refused(
            name: "a protocol that inherits another",
            source: """
                @GenerateSpies
                protocol Child: Base, Sendable {
                    func ping()
                }
                """,
            message: "'Child' inherits 'Base', whose requirements this macro can't see; "
                + "use @GenerateSpies on a class or an actor that conforms to 'Child' instead",
            line: 2,
            column: 15
        ),
    ]

    /// A double whose one property, on line 3, the macros can't write.
    private static func refusedProperty(
        _ name: String,
        _ property: String,
        _ message: String,
        column: Int
    ) -> Refused {
        refusedRequirement(name, property, message, column: column, marker: "@SpiedProperty")
    }

    /// A double whose one requirement, on line 3, the macros can't write.
    private static func refusedRequirement(
        _ name: String,
        _ requirement: String,
        _ message: String,
        column: Int,
        marker: String = "@Spied"
    ) -> Refused {
        Refused(
            name: name,
            source: """
                @GenerateSpies
                final class SpyStore: Store {
                    \(marker.isEmpty ? "" : marker + " ")\(requirement)
                }
                """,
            message: message,
            line: 3,
            column: column
        )
    }
}
