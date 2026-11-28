//
//  InitRequirementExpansionTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
import UnderstudyMacros

/// The parts of a protocol's spy that its `init` requirements decide. Each test checks the lines
/// that matter, never the whole expansion; the refusals are among `ExpansionTests.refused`.
@Suite("Macros write a protocol's init requirements")
struct InitRequirementExpansionTests {
    @Test("A public protocol's init is public, beside the spy's own initializer")
    func publicInitBesideTheOwnInitializer() {
        let (expanded, diagnostics) = expand(
            """
            @GenerateSpies
            public protocol Session {
                init(user: String) throws
                func ping() -> Int
                var name: String { get }
            }
            """
        )

        #expect(diagnostics.isEmpty)
        #expect(expanded.description.contains("public convenience init(user: String) throws {"))
    }

    @Test("Beside the protocol's init(), with no answers to take, no init is a convenience init")
    func initWithNoAnswersToTake() {
        let (delegating, delegatingDiagnostics) = expand(
            "@GenerateSpies\nprotocol Session {\n    init(user: String)\n}"
        )
        let (designated, designatedDiagnostics) = expand(
            "@GenerateSpies\nprotocol Session {\n    init()\n    init(user: String, age: Int)\n}"
        )

        #expect(delegatingDiagnostics.isEmpty)
        #expect(designatedDiagnostics.isEmpty)
        #expect(delegating.description.contains("convenience init(user: String) {"))
        #expect(!designated.description.contains("convenience"))
    }

    @Test("An actor's init delegates without the convenience keyword")
    func actorInitDelegatesWithoutConvenience() {
        let (expanded, diagnostics) = expand(
            "@GenerateSpies\nprotocol Store: Actor {\n    init(owner: String)\n    func total() -> Int\n}"
        )

        #expect(diagnostics.isEmpty)
        #expect(!expanded.description.contains("convenience"))
    }

    @Test("An async init and a typed throws init are written with no diagnostic")
    func asyncAndTypedThrowsInits() {
        let (_, diagnostics) = expand(
            """
            @GenerateSpies
            protocol Connection {
                init(host: String) async
                init(port: Int) throws(ConnectionError)
            }
            """
        )

        #expect(diagnostics.isEmpty)
    }

    // The isolation these shapes are written with is checked where the compiler builds the
    // doubles, in `InitRequirementTests` and `StaticDoubleTests`.
    @Test("Inits and statics under a global actor or in an actor are written with no diagnostic")
    func isolatedShapesAreWritten() {
        let sources = [
            "@MainActor\n@GenerateSpies\nprotocol Banner {\n    init(text: String)\n}",
            "@MainActor\n@GenerateSpies\nprotocol Badge {\n    nonisolated init(label: String)\n    func show()\n}",
            "@GenerateSpies\nprotocol Logbook: Actor {\n    nonisolated(nonsending) init(owner: String) async\n"
                + "    func total() -> Int\n}",
            "@GenerateSpies\nfinal class SpyFeed: Feed {\n    @Spied nonisolated(nonsending) func load() async\n}",
            "@MainActor\n@GenerateSpies\nfinal class SpyClock: Clock {\n    @Spied static func now() -> Int\n}",
        ]

        for source in sources {
            let (_, diagnostics) = expand(source)
            #expect(diagnostics.isEmpty, "\(source)")
        }
    }

    @Test("A protocol with an init can't be forwarded to, and its forwarding protocol says why")
    func protocolWithAnInitIsNotForwardedTo() {
        let (expanded, _) = expand("@GenerateSpies\nprotocol Session {\n    init(user: String)\n}")

        let message =
            "@GenerateSpies: 'Session' declares an init, so the spy of a protocol that inherits it can't "
            + "forward to its spy; use @GenerateSpies on a class or an actor that conforms to that protocol"
        #expect(expanded.description.contains("@available(*, unavailable, message: \"\(message)\")"))
        #expect(!expanded.description.contains("where Self:"))
    }

    // Expands the macros in `source`, and gives the expanded file and the messages of its
    // diagnostics.
    private func expand(_ source: String) -> (Syntax, [String]) {
        let file = Parser.parse(source: source)
        let known = BasicMacroExpansionContext.KnownSourceFile(moduleName: "TestModule", fullFilePath: "test.swift")
        let sourceFiles = [file: known]
        let context = BasicMacroExpansionContext(sourceFiles: sourceFiles)
        let macroSpecs = [
            "GenerateSpies": MacroSpec(type: GenerateSpiesMacro.self),
            "Spied": MacroSpec(type: SpiedMacro.self),
        ]
        let expanded = file.expand(
            macroSpecs: macroSpecs,
            contextGenerator: { syntax in
                BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
            },
            indentationWidth: .spaces(4)
        )
        return (expanded, context.diagnostics.map(\.message))
    }
}
