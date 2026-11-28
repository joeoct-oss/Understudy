//
//  SampleExpansionTests.swift
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
import UnderstudySamplesMacros

/// What a person writing `@Sample` sees from the macro: every struct it can write a sample for is
/// accepted, the sample is in debug builds only and as visible as the struct, and everything it
/// can't write is refused where the problem is, with what to do instead. What the samples hold is
/// tested where the compiler builds them, in `SampleTests`.
@Suite("@Sample accepts what it can write and explains what it can't")
struct SampleExpansionTests {
    /// A struct the macro must accept.
    struct Accepted: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String

        var testDescription: String {
            name
        }
    }

    /// A declaration the macro must refuse, with the message and where it points.
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

    @Test("Sample accepts every struct it can write", arguments: accepted)
    func acceptsEveryStructItCanWrite(_ sample: Accepted) {
        let (expanded, diagnostics) = expand(sample.source)

        #expect(diagnostics.isEmpty)
        #expect(!expanded.hasError)
        #expect(sampleFunction(in: expanded) != nil)
    }

    /// A release build must carry no `sample(...)`, and an app target must still build in release.
    @Test("The sample is written for debug builds only")
    func sampleIsWrittenForDebugBuildsOnly() throws {
        let (expanded, _) = expand(
            """
            @Sample
            struct Seller {
                let name: String
            }
            """
        )

        let function = try #require(sampleFunction(in: expanded))
        let clause = sequence(first: Syntax(function), next: \.parent)
            .lazy
            .compactMap { element in element.as(IfConfigClauseSyntax.self) }
            .first
        #expect(clause?.condition?.trimmedDescription == "DEBUG")
        #expect(clause?.poundKeyword.tokenKind == .poundIf)
    }

    /// A test that imports the module without `@testable` can call the sample of a public or
    /// package struct, and an internal struct's sample stays internal.
    @Test("The sample is as visible as its struct", arguments: visibilities)
    func sampleIsAsVisibleAsItsStruct(declaration: String, access: String?) throws {
        let (expanded, _) = expand(
            """
            @Sample
            \(declaration) Seller {
                let name: String
            }
            """
        )

        let function = try #require(sampleFunction(in: expanded))
        let levels = ["public", "package", "internal", "fileprivate", "private"]
        let written = function.modifiers.first { modifier in levels.contains(modifier.name.text) }?.name.text
        #expect(written == access)
    }

    /// Only `@SampleDefault` picks a property's sample value; another attribute's argument, such
    /// as a property wrapper's, is not one.
    @Test("Only @SampleDefault picks a sample value, not another attribute's argument")
    func onlySampleDefaultPicksTheValue() throws {
        let (expanded, _) = expand(
            """
            @Sample
            struct Seller {
                @Clamped(9) var rating: Int
            }
            """
        )

        let function = try #require(sampleFunction(in: expanded))
        #expect(function.signature.trimmedDescription.contains("rating: Int = 0"))
    }

    @Test("Sample refuses what it can't write, where the problem is", arguments: refused)
    func refusesWhatItCannotWriteWhereTheProblemIs(_ sample: Refused) {
        let (_, diagnostics) = expand(sample.source)

        let expected = ["\(sample.line):\(sample.column): understudy.error: @Sample: \(sample.message)"]
        #expect(diagnostics == expected)
    }

    /// The `sample(...)` function in an expanded file, if the macro wrote one.
    private func sampleFunction(in file: Syntax) -> FunctionDeclSyntax? {
        file.tokens(viewMode: .sourceAccurate)
            .first { token in
                token.tokenKind == .identifier("sample") && token.parent?.is(FunctionDeclSyntax.self) == true
            }?
            .parent?.as(FunctionDeclSyntax.self)
    }

    /// Expands the macros in `source`, and gives the expanded file and each diagnostic as
    /// "line:column: source: message", where the source is "understudy.error" for an error with
    /// Understudy's identifier.
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
            let isError = diagnostic.diagnosticID == Self.understudyError && diagnostic.diagMessage.severity == .error
            let source = isError ? "understudy.error" : "other"
            return "\(location.line):\(location.column): \(source): \(diagnostic.message)"
        }
        return (expanded, diagnostics)
    }

    /// The identifier of every error Understudy reports, so tools can tell its errors apart.
    private static let understudyError = MessageID(domain: "Understudy", id: "error")

    private static let macros: [String: MacroSpec] = [
        "Sample": MacroSpec(type: SampleMacro.self),
        "SampleDefault": MacroSpec(type: SampleDefaultMacro.self),
    ]

    /// Each way a struct is declared, and the access level its sample must have.
    static let visibilities: [(declaration: String, access: String?)] = [
        ("public struct", "public"),
        ("package struct", "package"),
        ("struct", nil),
        ("private struct", nil),
    ]

    static let accepted: [Accepted] = [
        Accepted(
            name: "a property of every type with a fixed default",
            source: """
                @Sample
                struct Defaults {
                    let text: String
                    let slice: Substring
                    let flag: Bool
                    let int: Int
                    let int8: Int8
                    let int16: Int16
                    let int32: Int32
                    let int64: Int64
                    let uint: UInt
                    let uint8: UInt8
                    let uint16: UInt16
                    let uint32: UInt32
                    let uint64: UInt64
                    let double: Double
                    let float: Float
                    let cgFloat: CGFloat
                    let decimal: Decimal
                    let date: Date
                    let id: UUID
                    let link: URL
                    let note: String?
                    let forced: String!
                    let spelled: Optional<String>
                    let list: [String]
                    let table: [String: Int]
                    let set: Set<Int>
                    let array: Array<Int>
                    let dictionary: Dictionary<String, Int>
                    let seller: Seller
                }
                """
        ),
        Accepted(
            name: "properties the memberwise initializer leaves out or fills",
            source: """
                @Sample
                struct Counter {
                    static let limit = 10
                    lazy var cache: [Int] = []
                    let kind = "counter"
                    var stock: Int = 5
                    @SampleDefault("EGP") let currency: String
                    @UnderstudySamples.SampleDefault(4.5) var rating: Double
                    var value: Int {
                        didSet {
                            print(value)
                        }
                    }
                    var doubled: Int {
                        value * 2
                    }
                    var tripled: Int {
                        get {
                            value * 3
                        }
                    }
                    func reset() { }
                }
                """
        ),
        Accepted(
            name: "a struct with no stored properties",
            source: """
                @Sample
                struct Empty { }
                """
        ),
    ]

    static let refused: [Refused] = [
        Refused(
            name: "a class",
            source: """
                @Sample
                final class Seller {
                    let name: String
                }
                """,
            message: "attach it to a struct; only a struct has a memberwise initializer to call",
            line: 1,
            column: 1
        ),
        Refused(
            name: "an enum",
            source: """
                @Sample
                enum Kind {
                    case physical
                }
                """,
            message: "attach it to a struct; only a struct has a memberwise initializer to call",
            line: 1,
            column: 1
        ),
        Refused(
            name: "a stored property with no type",
            source: """
                @Sample
                struct Product {
                    var stock = 5
                }
                """,
            message: "give 'stock' a type, because its sample(...) parameter needs one",
            line: 3,
            column: 9
        ),
        Refused(
            name: "a tuple of stored properties",
            source: """
                @Sample
                struct Point {
                    let (x, y): (Int, Int)
                }
                """,
            message: "declare each property on its own, such as 'let x: Int', so each gets its own "
                + "sample(...) parameter",
            line: 3,
            column: 9
        ),
    ]
}
