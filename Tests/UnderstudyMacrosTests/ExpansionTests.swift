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
        #expect(!expanded.description.contains("fatalError"))
    }

    @Test(arguments: refused)
    func refusesWhatItCannotWriteAtTheRequirement(_ double: Refused) {
        let (_, diagnostics) = expand(double.source)

        let expected = [
            "\(double.line):\(double.column): understudy.error: @Understudy: \(double.message)",
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
        "Understudy": MacroSpec(type: UnderstudyMacro.self),
        "Spied": MacroSpec(type: SpiedMacro.self),
    ]

    static let accepted: [Accepted] = [
        Accepted(
            name: "requirements with and without answers to give",
            source: """
                @Understudy
                final class SpyCatalog: Catalog {
                    @Spied func product(id: Int) -> String
                    @Spied func search(for query: String, limit: Int) -> String?
                    @Spied func refresh()
                }
                """
        ),
        Accepted(
            name: "overloads with different labels",
            source: """
                @Understudy
                final class SpyCatalog: Catalog {
                    @Spied func remove(id: Int)
                    @Spied func remove(named name: String)
                }
                """
        ),
        Accepted(
            name: "throwing and async requirements",
            source: """
                @Understudy
                final class SpyLoader: Loader {
                    @Spied func load(path: String) async throws -> String
                }
                """
        ),
        Accepted(
            name: "closures in and out, variadic and opaque parameters",
            source: """
                @Understudy
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
                @Understudy
                @MainActor
                open class SpyGate: Gate {
                    @Spied nonisolated func isOpen() -> Bool
                    @Spied func open()
                }

                @Understudy
                private final class SpyLog: Log {
                    @Spied func write(_ text: String)
                }
                """
        ),
        Accepted(
            name: "protocols you own",
            source: """
                @Understudy
                @MainActor
                public protocol Clock: AnyObject {
                    func now() -> Int
                    func sleep(for seconds: Int) async throws
                }

                @Understudy
                fileprivate protocol EventSink: Sendable {
                    func send(_ event: String)
                }
                """
        ),
    ]

    static let refused: [Refused] = [
        refusedRequirement("a generic requirement", "func load<Value>(_ key: String) -> Value",
                           "'load' is generic; write its double by hand", column: 17),
        refusedRequirement("a static requirement", "static func shared() -> Int",
                           "'shared' is static; write its double by hand", column: 24),
        refusedRequirement("a mutating requirement", "mutating func reset()",
                           "'reset' is mutating; @Understudy writes classes", column: 26),
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
        Refused(
            name: "overloads that differ only in their types",
            source: """
                @Understudy
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
                @Understudy
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
                @Understudy
                final class SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "mark each requirement to stand in for with @Spied, and give it no body",
            line: 1,
            column: 1
        ),
        Refused(
            name: "a struct",
            source: """
                @Understudy
                struct SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "attach it to a class or a protocol",
            line: 1,
            column: 1
        ),
        Refused(
            name: "@Spied outside an @Understudy class",
            source: """
                final class Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @Understudy on the class it is in",
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
            message: "@Spied needs @Understudy on the class it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied on something that isn't a function",
            source: """
                @Understudy
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
            name: "a protocol property",
            source: """
                @Understudy
                protocol Session {
                    var token: String { get }
                }
                """,
            message: "'Session' has a requirement that isn't a function; write its double by hand, "
                + "or use @Understudy on a class",
            line: 3,
            column: 5
        ),
        Refused(
            name: "a protocol that inherits another",
            source: """
                @Understudy
                protocol Child: Base, Sendable {
                    func ping()
                }
                """,
            message: "'Child' inherits 'Base', whose requirements this macro can't see; "
                + "use @Understudy on a class that conforms to 'Child' instead",
            line: 2,
            column: 15
        ),
    ]

    /// A double whose one requirement, on line 3, the macros can't write.
    private static func refusedRequirement(
        _ name: String,
        _ requirement: String,
        _ message: String,
        column: Int
    ) -> Refused {
        Refused(
            name: name,
            source: """
                @Understudy
                final class SpyStore: Store {
                    @Spied \(requirement)
                }
                """,
            message: message,
            line: 3,
            column: column
        )
    }
}
