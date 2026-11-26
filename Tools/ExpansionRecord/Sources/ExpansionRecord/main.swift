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
// With `--count`, prints how much code the macros write for those sources instead; with `--time`,
// how long expanding them all takes, as the median and range of 10 rounds after 3 warm-up rounds.
//
// Usage: ExpansionRecord [--count | --time] [--] <file.swift>...

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
    let known = BasicMacroExpansionContext.KnownSourceFile(moduleName: "RecordedModule", fullFilePath: "source.swift")
    let sourceFiles = [file: known]
    let context = BasicMacroExpansionContext(sourceFiles: sourceFiles)
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

    /// Keeps the literal, and skips what is inside it: a literal holds no other.
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        literals.append(node)
        return .skipChildren
    }
}

/// A source the macros expand: a whole file, or a string literal in one, with where it came from.
struct ExpandedSource {
    /// The file's path, and the literal's line after a colon.
    let place: String
    /// The Swift source the macros expand.
    let text: String
}

/// Every source in the file at `path` that uses a macro: the whole file, then each literal in it.
func sources(in path: String) throws -> [ExpandedSource] {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    guard usesMacro(source) else {
        return []
    }
    let literals = macroLiterals(in: Parser.parse(source: source)).map { literal in
        ExpandedSource(place: "\(path):\(literal.line)", text: literal.text)
    }
    return [ExpandedSource(place: path, text: source)] + literals
}

/// Prints each source's expansion and its diagnostics, under a line that names the source.
func printRecord(of all: [ExpandedSource]) {
    for source in all {
        let expanded = expansion(of: source.text)
        print("=== \(source.place)")
        print(expanded.code)
        expanded.diagnostics.forEach { print($0) }
    }
}

/// The number of lines in `text`.
func lineCount(_ text: String) -> Int {
    text.split(separator: "\n", omittingEmptySubsequences: false).count
}

/// The number of nodes in `text` that `counts`, nested ones included.
func count(in text: String, where counts: (Syntax) -> Bool) -> Int {
    count(in: Syntax(Parser.parse(source: text)), where: counts)
}

/// The number of nodes in `node` and everything under it that `counts`.
func count(in node: Syntax, where counts: (Syntax) -> Bool) -> Int {
    node.children(viewMode: .sourceAccurate).reduce(counts(node) ? 1 : 0) { total, child in
        total + count(in: child, where: counts)
    }
}

/// Whether `node` is a declaration.
func isDeclaration(_ node: Syntax) -> Bool {
    node.is(DeclSyntax.self)
}

/// Whether `node` is an attribute that names one of the package's macros.
func isMacroUse(_ node: Syntax) -> Bool {
    node.as(AttributeSyntax.self).map { macros[$0.attributeName.trimmedDescription] != nil } ?? false
}

/// Prints how many macro uses the sources hold, and the lines and declarations the macros add.
func printCount(of all: [ExpandedSource]) {
    let uses = all.reduce(0) { $0 + count(in: $1.text, where: isMacroUse) }
    let added = all.map { source in
        let code = expansion(of: source.text).code
        let declarations = count(in: code, where: isDeclaration) - count(in: source.text, where: isDeclaration)
        return (lineCount(code) - lineCount(source.text), declarations)
    }
    print("sources \(all.count)")
    print("macro uses \(uses)")
    print("lines written \(added.reduce(0) { $0 + $1.0 })")
    print("declarations written \(added.reduce(0) { $0 + $1.1 })")
}

/// Prints the median, fastest and slowest of 10 rounds that expand every source, after 3 rounds
/// to warm up, in milliseconds.
func printTime(of all: [ExpandedSource]) {
    let clock = ContinuousClock()
    let rounds = (0..<13).map { _ in
        clock.measure {
            for source in all {
                _ = expansion(of: source.text)
            }
        }
    }
    let kept = rounds.dropFirst(3).sorted()
    print("sources \(all.count)")
    print("median ms \(milliseconds((kept[4] + kept[5]) / 2))")
    print("fastest ms \(milliseconds(kept[0]))")
    print("slowest ms \(milliseconds(kept[9]))")
}

/// `duration` in milliseconds, to one decimal place.
func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.1f", Double(seconds) * 1e3 + Double(attoseconds) / 1e15)
}

let arguments = CommandLine.arguments.dropFirst()
let all = try arguments.filter { !$0.hasPrefix("--") }.flatMap(sources(in:))
if arguments.contains("--count") {
    printCount(of: all)
} else if arguments.contains("--time") {
    printTime(of: all)
} else {
    printRecord(of: all)
}
