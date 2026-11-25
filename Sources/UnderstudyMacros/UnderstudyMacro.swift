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

    /// The spies, the forwarders and the initializer, for a class or an actor.
    private static func members(of declaration: some DeclGroupSyntax) throws -> [DeclSyntax] {
        let isActor = declaration.is(ActorDeclSyntax.self)
        guard isActor || declaration.is(ClassDeclSyntax.self) else {
            if declaration.is(ProtocolDeclSyntax.self) {
                return []
            }
            throw UnderstudyError("attach it to a class, an actor or a protocol")
        }
        let requirements = try spiedRequirements(of: declaration.memberBlock)
        guard !requirements.isEmpty else {
            throw UnderstudyError("mark each function to stand in for with @Spied and give it no body, and each property with @SpiedProperty")
        }
        let names = try spyNames(for: requirements)
        let forwarders = zip(requirements, names).map { requirement, name in
            requirement.forwarder(spy: name)
        }
        return try storage(for: requirements, access: access(of: declaration.modifiers), isActor: isActor)
            + forwarders
    }

    /// The spy class written next to a protocol.
    private static func peers(of declaration: some DeclSyntaxProtocol) throws -> [DeclSyntax] {
        guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let inherited = proto.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        let isActor = inherited.contains { $0 == "Actor" || $0 == "_Concurrency.Actor" }
        let known = ["Sendable", "AnyObject", "Swift.Sendable", "Actor", "_Concurrency.Actor"]
        if let other = inherited.first(where: { !known.contains($0) }) {
            throw UnderstudyError(
                "'\(proto.name.text)' inherits '\(other)', whose requirements this macro can't see; "
                    + "use @Understudy on a class or an actor that conforms to '\(proto.name.text)' instead",
                at: proto.inheritanceClause
            )
        }
        let requirements: [any SpiedMember] = try proto.memberBlock.members.map { member in
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                return try Requirement(function)
            }
            if let property = member.decl.as(VariableDeclSyntax.self) {
                return try Property(property, inProtocol: true)
            }
            throw UnderstudyError(
                "'\(proto.name.text)' has a requirement that is neither a function nor a property; "
                    + "write its double by hand, or use @Understudy on a class or an actor",
                at: member.decl
            )
        }
        let access = access(of: proto.modifiers)
        let names = try spyNames(for: requirements)
        let members = try storage(for: requirements, access: access, isActor: isActor)
            + zip(requirements, names).map { requirement, name in
                requirement.implementation(spy: name, access: access)
            }
        let actors = proto.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
            .map { $0.trimmedDescription + "\n" }
            .joined()
        let prefix = access.isEmpty ? "" : access + " "
        let body = members.map { $0.trimmedDescription }.joined(separator: "\n\n")
        let name = proto.name.text
        let kind = isActor ? "actor" : "final class"
        return [
            """
            /// A spy for `\(raw: name)`, written by `@Understudy`.
            \(raw: actors)\(raw: prefix)\(raw: kind) \(raw: name)Spy: \(raw: name) {
            \(raw: body)
            }
            """,
        ]
    }

    /// The `@Spied` functions and properties of a class, in order.
    private static func spiedRequirements(of block: MemberBlockSyntax) throws -> [any SpiedMember] {
        try block.members.compactMap { member -> (any SpiedMember)? in
            if let property = member.decl.as(VariableDeclSyntax.self),
               property.attributes.contains(where: { isAttribute($0, named: "SpiedProperty") }) {
                return try Property(property, inProtocol: false)
            }
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  function.attributes.contains(where: { isAttribute($0, named: "Spied") }) else {
                return nil
            }
            guard function.body == nil else {
                throw UnderstudyError("'\(function.name.text)' is @Spied, so give it no body", at: function.name)
            }
            return try Requirement(function)
        }
    }

    /// Whether an attribute is `@<name>`, written alone or with the module's name.
    private static func isAttribute(_ element: AttributeListSyntax.Element, named name: String) -> Bool {
        let written = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
        return written == name || written == "Understudy." + name
    }

    /// One stored spy per requirement, and an initializer that asks for every answer with no safe
    /// default. An actor's spies are `nonisolated`, so a test reads them without `await`.
    private static func storage(
        for requirements: [any SpiedMember],
        access: String,
        isActor: Bool
    ) throws -> [DeclSyntax] {
        let names = try spyNames(for: requirements)
        let prefix = access.isEmpty ? "" : access + " "
        let spyPrefix = prefix + (isActor ? "nonisolated " : "")
        var declarations: [DeclSyntax] = []
        // A closure answer is taken `@escaping`, because the spy keeps it.
        var answers: [(name: String, output: String)] = []
        for (requirement, name) in zip(requirements, names) {
            if requirement.needsAnswer {
                declarations.append("\(raw: spyPrefix)let \(raw: name): \(raw: requirement.spyType)")
                answers.append((name, requirement.answerType))
            } else {
                declarations.append(
                    "\(raw: spyPrefix)let \(raw: name) = \(raw: requirement.spyType)(returning: \(raw: requirement.defaultAnswer))"
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

    /// The access level a generated member takes from the declaration it belongs to.
    static func access(of modifiers: DeclModifierListSyntax) -> String {
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
