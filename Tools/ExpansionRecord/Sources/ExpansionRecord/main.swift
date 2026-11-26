//
//  main.swift
//  ExpansionRecord
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import UnderstudyMacros
import UnderstudySamplesMacros

// Prints, for each Swift file given, what Understudy's macros write in it, in a stable order:
// - the whole file expanded, when it uses a macro, as the compiler would build it;
// - each string literal in it that holds a macro, as the macro tests expand it, with every
//   diagnostic: its place, message and fix-its.
// Files are read in the order given. A review aid, not a test: two records are compared with diff.
//
// Usage: ExpansionRecord <file.swift>...

/// Every macro the package declares, by the name a source writes it with.
let macros: [String: MacroSpec] = [
    "GenerateSpies": MacroSpec(type: GenerateSpiesMacro.self),
    "Spied": MacroSpec(type: SpiedMacro.self),
    "SpiedProperty": MacroSpec(type: SpiedPropertyMacro.self),
    "Sample": MacroSpec(type: SampleMacro.self),
    "SampleDefault": MacroSpec(type: SampleDefaultMacro.self),
]

/// Whether `source` writes one of the macros as an attribute.
func usesMacro(_ source: String) -> Bool {
    macros.keys.contains { source.contains("@" + $0) }
}

/// What the macros write for `source`, and every diagnostic they give, one per line.
func expansion(of source: String) -> (code: String, diagnostics: [String]) {
    let file = Parser.parse(source: source)
    let context = BasicMacroExpansionContext(
        sourceFiles: [file: .init(moduleName: "RecordedModule", fullFilePath: "source.swift")]
    )
    let expanded = file.expand(
        macroSpecs: macros,
        contextGenerator: { syntax in
            BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
        },
        indentationWidth: .spaces(4)
    )
    let diagnostics = context.diagnostics.map { diagnostic in
        describe(diagnostic, in: context)
    }
    return (expanded.description, diagnostics)
}

/// A diagnostic as "line:column: severity: message", then one line per fix-it.
func describe(_ diagnostic: Diagnostic, in context: BasicMacroExpansionContext) -> String {
    let location = context.location(for: diagnostic.position, anchoredAt: diagnostic.node, fileName: "source.swift")
    let head = "\(location.line):\(location.column): \(diagnostic.diagMessage.severity): \(diagnostic.message)"
    let fixIts = diagnostic.fixIts.map { fixIt in
        "  fix-it: \(fixIt.message.message)"
    }
    return ([head] + fixIts).joined(separator: "\n")
}

/// The text of every string literal in `file` that has no interpolation and holds a macro.
func macroLiterals(in file: SourceFileSyntax) -> [(line: Int, text: String)] {
    let finder = LiteralFinder(viewMode: .sourceAccurate)
    finder.walk(file)
    let converter = SourceLocationConverter(fileName: "", tree: file)
    return finder.literals.compactMap { literal in
        guard let text = literal.representedLiteralValue, usesMacro(text) else {
            return nil
        }
        return (literal.startLocation(converter: converter).line, text)
    }
}

/// Collects every string literal in a tree, in source order.
final class LiteralFinder: SyntaxVisitor {
    /// The literals found so far. `var` because each visit adds one.
    var literals: [StringLiteralExprSyntax] = []

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        literals.append(node)
        return .skipChildren
    }
}

/// Prints the record of one file.
func record(_ path: String) throws {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    guard usesMacro(source) else {
        return
    }
    let file = Parser.parse(source: source)
    let whole = expansion(of: source)
    print("=== \(path)")
    print(whole.code)
    whole.diagnostics.forEach { print($0) }
    for literal in macroLiterals(in: file) {
        let expanded = expansion(of: literal.text)
        print("=== \(path):\(literal.line)")
        print(expanded.code)
        expanded.diagnostics.forEach { print($0) }
    }
}

for path in CommandLine.arguments.dropFirst() {
    try record(path)
}
