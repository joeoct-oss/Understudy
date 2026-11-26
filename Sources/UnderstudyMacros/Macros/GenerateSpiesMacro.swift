//
//  GenerateSpiesMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@GenerateSpies`: on a class, adds a spy and a private forwarder for each `@Spied`
/// requirement; on a protocol, writes a spy class next to it.
///
/// - `MemberMacro`: writes the spies, the forwarders and the initializer into a class or an actor.
/// - `PeerMacro`: writes the spy class, and the protocol its children's spies forward through,
///   next to a protocol.
/// - `ExtensionMacro`: makes a class or an actor with static spies conform to `StaticSpies`, and
///   writes the extension that forwards a protocol's requirements to its spy.
public struct GenerateSpiesMacro: MemberMacro, PeerMacro, ExtensionMacro {
    /// The spies, the forwarders and the initializer, for a class.
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try reporting(in: context) {
            try members(of: declaration)
        }
    }

    /// The spy class, for a protocol.
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try reporting(in: context) {
            try peers(of: declaration, isNested: !context.lexicalContext.isEmpty)
        }
    }

    /// The conformance to `StaticSpies`, for a class or an actor with static spies, so
    /// `.freshSpies(_:)` can give each test its own; for a protocol, the extension that forwards
    /// its requirements to its spy, for the spy of a protocol that inherits it.
    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        if let proto = declaration.as(ProtocolDeclSyntax.self) {
            // `peers(of:)` reports a protocol the macro can't write.
            let spy = try? ProtocolSpy(proto, isNested: !context.lexicalContext.isEmpty)
            return spy?.forwardingExtension().map { [$0] } ?? []
        }
        guard declaration.is(ClassDeclSyntax.self) || declaration.is(ActorDeclSyntax.self),
              let requirements = try? spiedRequirements(of: declaration.memberBlock),
              requirements.contains(where: \.isStatic) else {
            return []
        }
        return [
            try ExtensionDeclSyntax("extension \(type.trimmed): \(raw: GeneratedName.staticSpies) {}"),
        ]
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
            context.diagnose(Diagnostic(node: node, message: error, fixIts: error.fixIt.map { [$0] } ?? []))
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
        let recorded = recordedProperties(of: declaration.memberBlock)
        try refuseRecorded(recorded, in: declaration, isActor: isActor)
        guard !requirements.isEmpty || !recorded.isEmpty else {
            throw UnderstudyError(
                "mark each function to stand in for with @Spied and give it no body, each property "
                    + "with @SpiedProperty or @Recorded, and the get and set of each subscript with @Spied"
            )
        }
        let names = try spyNames(for: requirements)
        let forwarders = zip(requirements, names).map { requirement, name in
            requirement.forwarder(spy: name)
        }
        let typeName = declaration.asProtocol(NamedDeclSyntax.self)?.name.text ?? ""
        let access = access(of: declaration.modifiers)
        return try storage(for: requirements, in: typeName, access: access, isActor: isActor)
            + forwarders
    }

    /// Refuses `@Recorded` on an actor, whose spy a test can't read without `await`, and on a
    /// `Sendable` class, with a fix-it that makes it `@SpiedProperty`.
    private static func refuseRecorded(
        _ recorded: [(IdentifierPatternSyntax, AttributeSyntax)],
        in declaration: some DeclGroupSyntax,
        isActor: Bool
    ) throws {
        let isSendable = declaration.inheritanceClause?.inheritedTypes.contains { inherited in
            ["Sendable", "Swift.Sendable"].contains(inherited.type.trimmedDescription)
        } == true
        guard let (property, attribute) = recorded.first, isActor || isSendable else {
            return
        }
        let why = isActor
            ? "whose spy a test can't read on an actor without await"
            : "which a Sendable class can't hold, because a wrapped property's storage is a var"
        let name = TokenSyntax.identifier("SpiedProperty", trailingTrivia: attribute.attributeName.trailingTrivia)
        let spied = attribute.with(\.attributeName, TypeSyntax(IdentifierTypeSyntax(name: name)))
        throw UnderstudyError(
            "'\(property.identifier.text)' is @Recorded, \(why); use @SpiedProperty",
            at: property,
            fixIt: .replace(
                message: UnderstudyFixIt("Replace '@Recorded' with '@SpiedProperty'"),
                oldNode: attribute,
                newNode: spied
            )
        )
    }

    /// The spy class written next to a protocol, and the protocol that lets the spy of a
    /// protocol inheriting this one forward to it.
    private static func peers(of declaration: some DeclSyntaxProtocol, isNested: Bool) throws -> [DeclSyntax] {
        guard let proto = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let spy = try ProtocolSpy(proto, isNested: isNested)
        let kind = spy.isActor ? "actor" : "final class"
        let members = try storage(
            for: spy.requirements,
            in: spy.spyName,
            access: spy.access,
            isActor: spy.isActor,
            parents: spy.parents
        ) + zip(spy.requirements, spy.spyNames).map { requirement, name in
            requirement.implementation(spy: name, access: spy.access)
        }
        let conformances = [spy.name] + spy.parents.map(\.forwarding)
            + (spy.requirements.contains(where: \.isStatic) ? [GeneratedName.staticSpies] : [])
        let body = members.map { $0.trimmedDescription }.joined(separator: "\n\n")
        let header = "\(spy.prefix)\(kind) \(spy.spyName)\(spy.genericParameters): "
            + conformances.joined(separator: ", ")
        return [
            """
            /// A spy for `\(raw: spy.name)`, written by `@GenerateSpies`.
            \(raw: spy.actors)\(raw: header) {
            \(raw: body)
            }
            """,
            spy.forwardingProtocol(),
        ]
    }

    /// The `@Spied` functions, properties and subscripts of a class, in order.
    private static func spiedRequirements(of block: MemberBlockSyntax) throws -> [any Requirement] {
        try block.members.compactMap { member -> (any Requirement)? in
            if let spied = member.decl.as(SubscriptDeclSyntax.self), hasSpiedAccessor(spied) {
                return try SubscriptRequirement(spied, inProtocol: false)
            }
            if let property = member.decl.as(VariableDeclSyntax.self),
               property.attributes.contains(where: { isAttribute($0, named: "SpiedProperty") }) {
                return try PropertyRequirement(property, inProtocol: false)
            }
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  function.attributes.contains(where: { isAttribute($0, named: "Spied") }) else {
                return nil
            }
            if let body = function.body {
                let bare = function.with(\.body, nil)
                    .with(\.signature, function.signature.with(\.trailingTrivia, []))
                    .with(\.trailingTrivia, body.trailingTrivia)
                throw UnderstudyError(
                    "'\(function.name.text)' is @Spied, so give it no body",
                    at: function.name,
                    fixIt: .replace(message: UnderstudyFixIt("Remove the body"), oldNode: function, newNode: bare)
                )
            }
            return try FunctionRequirement(function)
        }
    }

    /// The name and the attribute of every property marked `@Recorded`, which keeps its own spy, so
    /// the macro writes nothing for it.
    private static func recordedProperties(
        of block: MemberBlockSyntax
    ) -> [(IdentifierPatternSyntax, AttributeSyntax)] {
        block.members
            .compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .flatMap { variable -> [(IdentifierPatternSyntax, AttributeSyntax)] in
                guard let attribute = variable.attributes.lazy.compactMap({ $0.as(AttributeSyntax.self) })
                    .first(where: { isAttribute(.attribute($0), named: "Recorded") }) else {
                    return []
                }
                return variable.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self) }
                    .map { ($0, attribute) }
            }
    }

    /// Whether a subscript has an accessor marked `@Spied`.
    private static func hasSpiedAccessor(_ declaration: SubscriptDeclSyntax) -> Bool {
        let accessors = declaration.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) ?? []
        return accessors.contains { accessor in
            accessor.attributes.contains { isAttribute($0, named: "Spied") }
        }
    }

    /// Whether an attribute is `@<name>`, written alone or with the module's name.
    private static func isAttribute(_ element: AttributeListSyntax.Element, named name: String) -> Bool {
        let written = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
        return written == name || written == "Understudy." + name
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
