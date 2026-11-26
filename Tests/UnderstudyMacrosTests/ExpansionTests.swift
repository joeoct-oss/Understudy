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
    @Test("A generic answer of the wrong type gets a stop message naming the spy and both types")
    func genericAnswerOfTheWrongTypeStopsWithTheSpyAndBothTypes() {
        let (expanded, _) = expand("""
            @GenerateSpies
            final class SpyCache: Cache {
                @Spied func value<Value: Decodable>(for key: String) -> Value
            }
            """)

        let message = #"@GenerateSpies: valueSpy answered \(Swift.type(of: __understudy_answer)), not \(Value.self)"#
        #expect(expanded.description.contains(message))
    }

    /// An error of another type than a typed `throws` names stops the process too, so the test
    /// checks the double says which spy threw it, and both types.
    @Test("A typed throws error of another type gets a stop message naming the spy and both types")
    func typedThrowsWithAnotherErrorTypeStopsNamingTheSpy() {
        let (expanded, _) = expand("""
            @GenerateSpies
            final class SpyAuth: Auth {
                @Spied func signIn(email: String) async throws(AuthError) -> String
            }
            """)

        let message = #"@GenerateSpies: signInSpy threw \(Swift.type(of: error)), not \(AuthError.self)"#
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

    /// The constraints of an associated type stay on the spy's generic parameter, so the compiler
    /// keeps a test from making a spy of a type the protocol doesn't allow; with a `Sendable`
    /// protocol, the parameter is `Sendable` too, because the spy stores values of it. The test
    /// checks the class the macro declares, which a running test can't see.
    @Test(
        "An associated type keeps its constraints on the spy, with Sendable for a Sendable protocol",
        arguments: constrained
    )
    func associatedTypeKeepsItsConstraints(_ opening: String, _ declared: String) {
        let (expanded, diagnostics) = expand("""
            @GenerateSpies
            \(opening)
                associatedtype Item: Equatable, Codable
                associatedtype Key
                func item(for key: Key) -> Item?
            }
            """)

        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("final class " + declared))
    }

    /// A parent's answer may have no obvious default, so the child's spy can't make the parent's
    /// spy itself: its initializer asks for each one, first, with no default.
    @Test("The child's spy initializer asks for each parent's spy, with no default")
    func parentSpyArgumentIsRequired() {
        let (expanded, _) = expand("""
            @GenerateSpies
            protocol Child: Base, URLLoader {
                func count() -> Int
            }
            """)

        let initializer = "init(base: BaseSpy, urlLoader: URLLoaderSpy, count: Int = 0)"
        #expect(expanded.description.contains(initializer))
    }

    /// A child's spy may sit wherever the parent's spy does, so the forwarding protocol and its
    /// extension keep the parent's access level and global actor; the test checks what the
    /// macro declares, which a running test in one module can't see.
    @Test("The forwarding protocol keeps the parent's access level and global actor")
    func forwardingKeepsTheParentsAccessAndActor() {
        let (expanded, _) = expand("""
            @GenerateSpies
            @MainActor
            public protocol Screen {
                func show()
            }
            """)

        let forwarding = "@MainActor\npublic protocol ScreenSpyForwarding: Screen, AnyObject"
        let extended = "@MainActor\nextension Screen where Self: ScreenSpyForwarding"
        #expect(expanded.description.contains(forwarding))
        #expect(expanded.description.contains(extended))
        #expect(expanded.description.contains("public func show()"))
    }

    /// A protocol whose spy can't be forwarded to still gets a forwarding protocol, unavailable,
    /// so a child protocol's spy fails to build with a message saying why, instead of "cannot
    /// find 'XSpyForwarding'".
    @Test(
        "A protocol whose spy can't be forwarded to gets an unavailable forwarding protocol that says why",
        arguments: unforwardable
    )
    func parentThatCantBeForwardedIsRefusedForItsChild(_ opening: String, _ why: String) {
        let closing = opening.hasPrefix("enum") ? "}\n}" : "}"
        let source = (opening.hasPrefix("enum") ? "" : "@GenerateSpies\n") + opening + "\nfunc ping()\n" + closing
        let (expanded, diagnostics) = expand(source)

        let message = "@GenerateSpies: \(why), so the spy of a protocol that inherits it can't forward to its "
            + "spy; use @GenerateSpies on a class or an actor that conforms to that protocol"
        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("@available(*, unavailable, message: \"\(message)\")"))
        #expect(!expanded.description.contains("where Self:"))
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

    /// A refusal with one clear fix, and the double once the fix-it is applied.
    struct Fixed: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let fixIt: String
        let fixed: String

        var testDescription: String {
            name
        }
    }

    @Test("Each refusal with one clear fix offers it, and applying it gives the fixed code", arguments: fixed)
    func eachRefusalWithOneFixOffersIt(_ double: Fixed) throws {
        let file = Parser.parse(source: double.source)
        let context = BasicMacroExpansionContext(
            sourceFiles: [file: .init(moduleName: "TestModule", fullFilePath: "test.swift")]
        )
        _ = file.expand(
            macroSpecs: Self.macros,
            contextGenerator: { syntax in
                BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
            },
            indentationWidth: .spaces(4)
        )
        let fixIts = context.diagnostics.flatMap(\.fixIts)
        let fixIt = try #require(fixIts.first)
        var source = Array(double.source.utf8)
        for case .replace(let old, let new) in fixIt.changes {
            let start = context.location(for: old.position, anchoredAt: old, fileName: "test.swift").offset
            source.replaceSubrange(start..<start + old.totalLength.utf8Length, with: Array(new.description.utf8))
        }

        #expect(fixIts.count == 1)
        #expect(fixIt.message.message == double.fixIt)
        #expect(fixIt.message.fixItID == MessageID(domain: "Understudy", id: "fix-it"))
        #expect(String(decoding: source, as: UTF8.self) == double.fixed)
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

    /// How a protocol opens, and the spy class its associated types give.
    static let constrained = [
        ("protocol Repository {", "RepositorySpy<Item: Equatable & Codable, Key>: Repository"),
        (
            "protocol Repository: Sendable {",
            "RepositorySpy<Item: Equatable & Codable & Swift.Sendable, Key: Swift.Sendable>"
        ),
    ]

    /// How a protocol whose spy can't be forwarded to opens, and why it can't.
    static let unforwardable = [
        ("protocol Repository {\n    associatedtype Item", "'Repository' has associated types"),
        ("protocol Store: Actor {", "'Store' is an actor protocol"),
        ("enum Shop {\n@GenerateSpies\nprotocol Repository {", "'Repository' is declared inside another type"),
    ]

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

    static let fixed: [Fixed] = [
        fixedMember("a let", "@SpiedProperty let token: String", "Replace 'let' with 'var'",
                    "@SpiedProperty var token: String"),
        fixedMember("a body", "@Spied func write(_ text: String) {}", "Remove the body",
                    "@Spied func write(_ text: String)"),
        fixedMember("a parameter with no name", "@Spied func move(_: Int)", "Add a name",
                    "@Spied func move(_ <#name#>: Int)"),
        fixedMember("a property with no type", "@SpiedProperty var token", "Add a type",
                    "@SpiedProperty var token: <#Type#>"),
        fixedMember("a property with a value and no type", "@SpiedProperty var token = 0", "Add a type",
                    "@SpiedProperty var token: <#Type#> = 0"),
        Fixed(
            name: "@Recorded in an actor",
            source: "@GenerateSpies\nactor SpyStore {\n    @Recorded var count = 0\n}",
            fixIt: "Replace '@Recorded' with '@SpiedProperty'",
            fixed: "@GenerateSpies\nactor SpyStore {\n    @SpiedProperty var count = 0\n}"
        ),
        Fixed(
            name: "@Recorded in a Sendable class",
            source: "@GenerateSpies\nfinal class SpyStore: Sendable {\n    @Understudy.Recorded var count = 0\n}",
            fixIt: "Replace '@Recorded' with '@SpiedProperty'",
            fixed: "@GenerateSpies\nfinal class SpyStore: Sendable {\n    @SpiedProperty var count = 0\n}"
        ),
    ]

    /// A double whose one member, on line 3, is refused with a fix-it that makes it `fixed`.
    private static func fixedMember(_ name: String, _ member: String, _ fixIt: String, _ fixed: String) -> Fixed {
        let double = { (member: String) in "@GenerateSpies\nfinal class SpyStore: Store {\n    \(member)\n}" }
        return Fixed(name: name, source: double(member), fixIt: fixIt, fixed: double(fixed))
    }

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
        refusedRequirement("a static requirement with no obvious answer", "static func now() -> Date",
                           "'now' is static, so no initializer takes its first answer, and 'Date' has no "
                               + "obvious one; make it optional, or write its double by hand", column: 24),
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
        refusedProperty("a static property with no obvious value", "static var zone: TimeZone",
                        "'zone' is static, so no initializer takes its first answer, and 'TimeZone' has no "
                            + "obvious one; make it optional, or write its double by hand", column: 31),
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
            name: "@Recorded in a Sendable class",
            source: """
                @GenerateSpies
                final class SpySession: Session, Sendable {
                    @Recorded var user = "ana"
                }
                """,
            message: "'user' is @Recorded, which a Sendable class can't hold, because a wrapped property's "
                + "storage is a var; use @SpiedProperty",
            line: 3,
            column: 19
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
        refusedProtocol(
            "an associated type with a where clause",
            "protocol Repository {\n    associatedtype Item where Item: Codable",
            "'Item' has a where clause, which a generic parameter can't keep; "
                + "\(classForm) 'Repository' instead",
            line: 3,
            column: 20
        ),
        refusedProtocol(
            "a protocol where clause next to an associated type",
            "protocol Repository where Item: Codable {\n    associatedtype Item",
            "'Repository' has a where clause, which the spy's generic parameters can't keep; "
                + "\(classForm) 'Repository' instead",
            line: 2,
            column: 21
        ),
        refusedProtocol(
            "a static requirement next to an associated type",
            "protocol Repository {\n    associatedtype Item\n    static func make() -> Item?",
            "'make' is static, and a spy with associated types is generic, so it can't keep a static "
                + "spy; \(classForm) 'Repository' instead",
            line: 4,
            column: 17
        ),
        refusedProtocol(
            "a standard library parent",
            "protocol Account: Identifiable {",
            "'Account' inherits 'Identifiable', which has no spy to forward to; \(classForm) 'Account' instead",
            line: 2,
            column: 19
        ),
        refusedProtocol(
            "a parent written with its associated types",
            "protocol Shelf: Box<Int> {",
            "'Shelf' inherits 'Box<Int>', which has associated types, so its spy can't forward to "
                + "that one's spy; \(classForm) 'Shelf' instead",
            line: 2,
            column: 17
        ),
        refusedProtocol(
            "an actor protocol that inherits another",
            "protocol Store: Actor, Base {",
            "'Store' is an actor protocol that inherits 'Base', which its spy can't forward to across "
                + "the actor; \(classForm) 'Store' instead",
            line: 2,
            column: 24
        ),
    ]

    /// What every refusal of a protocol the class form can write says to do instead.
    private static let classForm = "use @GenerateSpies on a class or an actor that conforms to"

    /// A protocol whose declaration starts with `opening`, and which has one function, that the
    /// macros can't write.
    private static func refusedProtocol(
        _ name: String,
        _ opening: String,
        _ message: String,
        line: Int,
        column: Int
    ) -> Refused {
        Refused(
            name: name,
            source: """
                @GenerateSpies
                \(opening)
                    func ping()
                }
                """,
            message: message,
            line: line,
            column: column
        )
    }

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
