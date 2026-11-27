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
        let (expanded, _) = expand(
            """
            @GenerateSpies
            final class SpyCache: Cache {
                @Spied func value<Value: Decodable>(for key: String) -> Value
            }
            """
        )

        let message = #"@GenerateSpies: valueSpy answered \(Swift.type(of: __understudy_answer)), not \(Value.self)"#
        #expect(expanded.description.contains(message))
    }

    /// An error of another type than a typed `throws` names stops the process too, so the test
    /// checks the double says which spy threw it, and both types.
    @Test("A typed throws error of another type gets a stop message naming the spy and both types")
    func typedThrowsWithAnotherErrorTypeStopsNamingTheSpy() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            final class SpyAuth: Auth {
                @Spied func signIn(email: String) async throws(AuthError) -> String
            }
            """
        )

        let message = #"@GenerateSpies: signInSpy threw \(Swift.type(of: error)), not \(AuthError.self)"#
        #expect(expanded.description.contains(message))
    }

    /// A get-only subscript of a protocol has no setter, so its spy class gets no set spy.
    @Test("A get-only subscript gets no set spy")
    func getOnlySubscriptHasNoSetSpy() {
        let (expanded, diagnostics) = expand(
            """
            @GenerateSpies
            protocol Table {
                subscript(row: Int) -> String { get }
            }
            """
        )

        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("subscriptSpy"))
        #expect(!expanded.description.contains("subscriptSetSpy"))
    }

    /// The constraints of an associated type stay on the spy's generic parameter, so the compiler
    /// keeps a test from making a spy of a type the protocol doesn't allow; with a `Sendable`
    /// protocol, the parameter is `Sendable` too, because the spy stores values of it, and one
    /// already `Sendable` gets nothing added. The test checks the class the macro declares, which
    /// a running test can't see.
    @Test(
        "An associated type keeps its constraints on the spy, with Sendable for a Sendable protocol",
        arguments: constrained
    )
    func associatedTypeKeepsItsConstraints(_ opening: String, _ declared: String) {
        let (expanded, diagnostics) = expand(
            """
            @GenerateSpies
            \(opening)
                associatedtype Item: Equatable, Codable
                associatedtype Key
                associatedtype Tag: Sendable
                func item(for key: Key) -> Item?
            }
            """
        )

        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("final class " + declared))
    }

    /// A parent's answer may have no obvious default, so the child's spy can't make the parent's
    /// spy itself: its initializer asks for each one, first, with no default.
    @Test("The child's spy initializer asks for each parent's spy, with no default")
    func parentSpyArgumentIsRequired() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            protocol Child: Base, URLLoader, API {
                func count() -> Int
            }
            """
        )

        let initializer = "init(base: BaseSpy, urlLoader: URLLoaderSpy, api: APISpy, count: Int = 0)"
        #expect(expanded.description.contains(initializer))
    }

    /// A child's spy may sit wherever the parent's spy does, so the forwarding protocol and its
    /// extension keep the parent's access level and global actor; the test checks what the
    /// macro declares, which a running test in one module can't see.
    @Test("The forwarding protocol keeps the parent's access level and global actor")
    func forwardingKeepsTheParentsAccessAndActor() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            @MainActor
            public protocol Screen {
                func show()
            }
            """
        )

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

        let message =
            "@GenerateSpies: \(why), so the spy of a protocol that inherits it can't forward to its "
            + "spy; use @GenerateSpies on a class or an actor that conforms to that protocol"
        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("@available(*, unavailable, message: \"\(message)\")"))
        #expect(!expanded.description.contains("where Self:"))
    }

    /// A type with no obvious value stays a required argument of the initializer, so the compiler
    /// still asks for it; a standard type gets its value however it is written. The test checks
    /// the initializer the double declares.
    @Test("The initializer asks for a type with no obvious default and defaults the rest")
    func initStillAsksForATypeWithNoObviousDefault() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            final class SpyCatalog: Catalog {
                @Spied func product(id: Int) -> Product
                @Spied func stock() -> Store.Int
                @Spied func count() -> Swift.Int
                @Spied func handler() -> () -> Void
                @Spied func list() -> Array<Int>
                @Spied func tags() -> Swift.Set<String>
                @Spied func map() -> Dictionary<String, Int>
                @Spied func name() -> String
            }
            """
        )

        let initializer =
            "init(product: Product, stock: Store.Int, count: Swift.Int = 0, "
            + "handler: @escaping () -> Void, list: Array<Int> = [], tags: Swift.Set<String> = [], "
            + #"map: Dictionary<String, Int> = [:], name: String = "")"#
        #expect(expanded.description.contains(initializer))
    }

    /// An optional and nothing have an obvious first answer however they are written, so the
    /// initializer doesn't ask for them.
    @Test("A requirement returning an optional or nothing, however written, needs no first answer")
    func optionalOrNothingNeedsNoFirstAnswer() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            final class SpyCatalog: Catalog {
                @Spied func nickname() -> Optional<String>
                @Spied func avatar() -> String!
                @Spied func reset() -> Void
                @Spied func clear() -> ()
                @Spied func name() -> String
            }
            """
        )

        #expect(expanded.description.contains(#"init(name: String = "")"#))
    }

    /// A public protocol's spy is public, subscripts too, so a test in another module can use it.
    @Test("A public protocol's subscript is public on its spy")
    func publicSubscriptIsPublicOnTheSpy() {
        let (expanded, _) = expand(
            """
            @GenerateSpies
            public protocol Table {
                subscript(row: Int) -> String { get }
            }
            """
        )

        #expect(expanded.description.contains("public subscript(row: Int) -> String"))
    }

    /// A refused property is left as written, so the person sees the refusal and nothing else.
    @Test("A refused property gets no setter, so the refusal is the only error")
    func refusedPropertyGetsNoSetter() {
        let (expanded, diagnostics) = expand(
            """
            @GenerateSpies
            final class SpyStore: Store {
                @SpiedProperty var token: String { get }
            }
            """
        )

        #expect(diagnostics.count == 1)
        #expect(!expanded.description.contains("set {"))
    }

    /// The body `@Spied` writes for a requirement `@GenerateSpies` refused.
    private static let refusedBody = "@GenerateSpies can't write this requirement"

    @Test("GenerateSpies refuses what it can't write, at the requirement", arguments: refused)
    func refusesWhatItCannotWriteAtTheRequirement(_ double: Refused) {
        let (_, diagnostics) = expand(double.source)

        let expected = [
            "\(double.line):\(double.column): understudy.error: @GenerateSpies: \(double.message)"
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
        ("protocol Repository {", "RepositorySpy<Item: Equatable & Codable, Key, Tag: Sendable>: Repository"),
        (
            "protocol Repository: AnyObject {",
            "RepositorySpy<Item: Equatable & Codable, Key, Tag: Sendable>: Repository"
        ),
        (
            "protocol Repository: Sendable {",
            "RepositorySpy<Item: Equatable & Codable & Swift.Sendable, Key: Swift.Sendable, Tag: Sendable>"
        ),
    ]

    /// How a protocol whose spy can't be forwarded to opens, and why it can't.
    static let unforwardable = [
        ("protocol Repository {\n    associatedtype Item", "'Repository' has associated types"),
        ("protocol Store: Actor {", "'Store' is an actor protocol"),
        ("enum Shop {\n@GenerateSpies\nprotocol Repository {", "'Repository' is declared inside another type"),
    ]

    static let fixed: [Fixed] = [
        fixedMember(
            "a let",
            "@SpiedProperty let token: String",
            "Replace 'let' with 'var'",
            "@SpiedProperty var token: String"
        ),
        fixedMember(
            "a body",
            "@Spied func write(_ text: String) {}",
            "Remove the body",
            "@Spied func write(_ text: String)"
        ),
        fixedMember(
            "a parameter with no name",
            "@Spied func move(_: Int)",
            "Add a name",
            "@Spied func move(_ <#name#>: Int)"
        ),
        fixedMember(
            "a property with no type",
            "@SpiedProperty var token",
            "Add a type",
            "@SpiedProperty var token: <#Type#>"
        ),
        fixedMember(
            "a property with a value and no type",
            "@SpiedProperty var token = 0",
            "Add a type",
            "@SpiedProperty var token: <#Type#> = 0"
        ),
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
}
