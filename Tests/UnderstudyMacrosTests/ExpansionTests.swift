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

    @Test(arguments: accepted)
    func acceptsEveryRequirementItCanWrite(_ double: Accepted) {
        let (expanded, diagnostics) = expand(double.source)

        #expect(diagnostics.isEmpty)
        #expect(!expanded.hasError)
        #expect(!expanded.description.contains(Self.refusedBody))
    }

    /// A generic answer of the wrong type can't be tested by calling it, because it stops the
    /// process. What the person sees is this message, so the test checks the double says it.
    @Test
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

    /// The body `@Spied` writes for a requirement `@GenerateSpies` refused.
    private static let refusedBody = "@GenerateSpies can't write this requirement"

    @Test(arguments: refused)
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
        refusedRequirement("a generic inside a parameter's type", "func save<Value>(_ values: [Value])",
                           "'save' uses 'Value' inside another type; write its double by hand", column: 39),
        refusedRequirement("a generic inside the return type", "func load<Value>(_ key: String) -> [Value]",
                           "'load' uses 'Value' inside another type; write its double by hand", column: 47),
        refusedRequirement("a static requirement", "static func shared() -> Int",
                           "'shared' is static; write its double by hand", column: 24),
        refusedRequirement("a mutating requirement", "mutating func reset()",
                           "'reset' is mutating; @GenerateSpies writes classes and actors", column: 26),
        refusedRequirement("typed throws", "func load() throws(LoadError) -> Int",
                           "'load' uses typed throws; write its double by hand", column: 17),
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
        refusedProperty("a property with a value", "var token: String = \"\"",
                        "'token' has a value; give it none, the double's initializer takes it", column: 24),
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
                + "and each property with @SpiedProperty",
            line: 1,
            column: 1
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
            message: "@Spied goes on a function",
            line: 4,
            column: 5
        ),
        Refused(
            name: "a protocol subscript",
            source: """
                @GenerateSpies
                protocol Session {
                    subscript(key: String) -> String { get }
                }
                """,
            message: "'Session' has a requirement that is neither a function nor a property; "
                + "write its double by hand, or use @GenerateSpies on a class or an actor",
            line: 3,
            column: 5
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
                    \(marker) \(requirement)
                }
                """,
            message: message,
            line: 3,
            column: column
        )
    }
}
