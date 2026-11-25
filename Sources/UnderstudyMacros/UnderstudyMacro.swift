//
//  UnderstudyMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Understudy`: on a class, adds a spy and a private forwarder for each `@Spied` requirement; on a
/// protocol, writes a spy class next to it.
public struct UnderstudyMacro: MemberMacro, PeerMacro {
    /// The spies, the forwarders and the initializer, for a class.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try reporting(in: context) {
            try members(of: declaration)
        }
    }

    /// The spy class, for a protocol.
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try reporting(in: context) {
            try peers(of: declaration)
        }
    }

    /// Reports an error about a requirement at the requirement, so the editor marks that line, and
    /// any other error at the attribute.
    private static func reporting(
        in context: some MacroExpansionContext,
        _ expand: () throws -> [DeclSyntax]
    ) throws -> [DeclSyntax] {
        do {
            return try expand()
        } catch let error as UnderstudyError {
            guard let node = error.node else {
                throw error
            }
            context.diagnose(Diagnostic(node: node, message: error))
            return []
        }
    }

    /// The spies, the forwarders and the initializer, for a class.
    private static func members(of declaration: some DeclGroupSyntax) throws -> [DeclSyntax] {
        guard let type = declaration.as(ClassDeclSyntax.self) else {
            if declaration.is(ProtocolDeclSyntax.self) {
                return []
            }
            throw UnderstudyError("attach it to a class or a protocol")
        }
        let requirements = try spiedRequirements(of: type.memberBlock)
        guard !requirements.isEmpty else {
            throw UnderstudyError("mark each requirement to stand in for with @Spied, and give it no body")
        }
        let names = try spyNames(for: requirements)
        let forwarders = zip(requirements, names).map { requirement, name in
            forwarder(for: requirement, spy: name)
        }
        return try storage(for: requirements, access: access(of: type.modifiers)) + forwarders
    }

    /// The spy class written next to a protocol.
    private static func peers(of declaration: some DeclSyntaxProtocol) throws -> [DeclSyntax] {
        guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let inherited = proto.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        if let other = inherited.first(where: { !["Sendable", "AnyObject", "Swift.Sendable"].contains($0) }) {
            throw UnderstudyError(
                "'\(proto.name.text)' inherits '\(other)', whose requirements this macro can't see; "
                    + "use @Understudy on a class that conforms to '\(proto.name.text)' instead",
                at: proto.inheritanceClause
            )
        }
        var requirements: [Requirement] = []
        for member in proto.memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                throw UnderstudyError(
                    "'\(proto.name.text)' has a requirement that isn't a function; "
                        + "write its double by hand, or use @Understudy on a class",
                    at: member.decl
                )
            }
            requirements.append(try Requirement(function))
        }
        let access = access(of: proto.modifiers)
        let names = try spyNames(for: requirements)
        let members = try storage(for: requirements, access: access)
            + zip(requirements, names).map { requirement, name in
                implementation(of: requirement, spy: name, access: access)
            }
        let actors = proto.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
            .map { $0.trimmedDescription + "\n" }
            .joined()
        let prefix = access.isEmpty ? "" : access + " "
        let body = members.map { $0.trimmedDescription }.joined(separator: "\n\n")
        let name = proto.name.text
        return [
            """
            /// A spy for `\(raw: name)`, written by `@Understudy`.
            \(raw: actors)\(raw: prefix)final class \(raw: name)Spy: \(raw: name) {
            \(raw: body)
            }
            """,
        ]
    }

    /// The `@Spied` functions of a class, in order.
    private static func spiedRequirements(of block: MemberBlockSyntax) throws -> [Requirement] {
        try block.members.compactMap { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  function.attributes.contains(where: isSpied) else {
                return nil
            }
            guard function.body == nil else {
                throw UnderstudyError("'\(function.name.text)' is @Spied, so give it no body", at: function)
            }
            return try Requirement(function)
        }
    }

    /// Whether an attribute is `@Spied`.
    private static func isSpied(_ element: AttributeListSyntax.Element) -> Bool {
        let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
        return name == "Spied" || name == "Understudy.Spied"
    }

    /// The private function a `@Spied` requirement's body calls: it takes the requirement's labels,
    /// keeps its isolation and its `throws`, and calls the spy.
    private static func forwarder(for requirement: Requirement, spy: String) -> DeclSyntax {
        let actors = requirement.declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
            .map { $0.trimmedDescription + " " }
            .joined()
        let isolation = requirement.declaration.modifiers.contains { $0.name.text == "nonisolated" }
            ? "nonisolated "
            : ""
        let effects = requirement.throwsError ? " throws" : ""
        let attempt = requirement.throwsError ? "try " : ""
        let signature = "\(requirement.forwarderName)(\(requirement.forwarderParameters))\(effects)"
        return """
            \(raw: actors)private \(raw: isolation)func \(raw: signature) -> \(raw: requirement.output) {
            return \(raw: attempt)self.\(raw: spy)(\(raw: requirement.callArgument))
            }
            """
    }

    /// One stored spy per requirement, and an initializer that asks for every answer with no safe
    /// default.
    private static func storage(for requirements: [Requirement], access: String) throws -> [DeclSyntax] {
        let names = try spyNames(for: requirements)
        let prefix = access.isEmpty ? "" : access + " "
        var declarations: [DeclSyntax] = []
        // A closure answer is taken `@escaping`, because the spy keeps it.
        var answers: [(name: String, output: String)] = []
        for (requirement, name) in zip(requirements, names) {
            if requirement.needsAnswer {
                declarations.append("\(raw: prefix)let \(raw: name): \(raw: requirement.spyType)")
                answers.append((name, (requirement.returnsFunction ? "@escaping " : "") + requirement.output))
            } else {
                let answer = requirement.returnsNothing ? "()" : "nil"
                declarations.append(
                    "\(raw: prefix)let \(raw: name) = \(raw: requirement.spyType)(returning: \(raw: answer))"
                )
            }
        }
        guard !answers.isEmpty else {
            return declarations
        }
        // The initializer names each answer after its requirement: `init(now:)` fills `nowSpy`.
        let parameters = answers.map { "\(label(of: $0.name)): \($0.output)" }.joined(separator: ", ")
        let assignments = answers.map { "self.\($0.name) = .init(returning: \(label(of: $0.name)))" }
            .joined(separator: "\n")
        declarations.append(
            """
            /// Creates the double with the answer each requirement gives until the test scripts another.
            \(raw: prefix)init(\(raw: parameters)) {
            \(raw: assignments)
            }
            """
        )
        return declarations
    }

    /// The initializer's label for a spy's answer: the spy's name without its suffix.
    private static func label(of spy: String) -> String {
        String(spy.dropLast(spySuffix.count))
    }

    /// A protocol requirement with its body, for the spy class.
    private static func implementation(of requirement: Requirement, spy: String, access: String) -> DeclSyntax {
        var function = requirement.declaration
        function.body = CodeBlockSyntax(statements: SpiedMacro.body(of: requirement, spy: spy))
        function.leadingTrivia = []
        if !access.isEmpty {
            function.modifiers.append(DeclModifierSyntax(name: .identifier(access), trailingTrivia: .space))
        }
        return DeclSyntax(function)
    }

    /// The access level a generated member takes from the declaration it belongs to.
    private static func access(of modifiers: DeclModifierListSyntax) -> String {
        let levels = ["open", "public", "package", "internal", "fileprivate", "private"]
        guard let level = modifiers.first(where: { levels.contains($0.name.text) })?.name.text else {
            return ""
        }
        switch level {
        case "open":
            return "public"
        case "private", "fileprivate":
            return "fileprivate"
        default:
            return level
        }
    }
}
