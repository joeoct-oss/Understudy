//
//  ProtocolSpy.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// A protocol `@GenerateSpies` writes a spy for, read from its declaration: its requirements, the
/// protocols it inherits and its associated types.
///
/// Next to every protocol it can forward, the macro also writes `<Name>SpyForwarding` and an
/// extension of the protocol for the types that adopt it. The spy of a protocol that inherits
/// this one stores this one's spy and adopts the forwarding protocol, so the extension answers
/// this one's requirements through that spy.
struct ProtocolSpy {
    /// A protocol this one inherits, whose spy the child's spy stores and forwards to.
    struct Parent {
        /// The parent as written, such as `Base`.
        let type: String
        /// The child spy's initializer label for the parent's spy, such as `base`.
        let label: String

        /// The parent's spy class.
        var spyType: String {
            type + spySuffix
        }

        /// The protocol that lets a child's spy forward to the parent's spy.
        var forwarding: String {
            forwardingName(of: type)
        }

        /// The child spy's stored property that holds the parent's spy, such as `baseSpy`.
        var property: String {
            label + spySuffix
        }
    }

    /// The protocols a spy class can adopt with nothing to forward: markers with no
    /// requirements, and `Actor`, which makes the spy an actor.
    private static let markers: Set = ["Sendable", "Swift.Sendable", "AnyObject", "Actor", "_Concurrency.Actor"]

    /// Standard library and Foundation protocols, which have no `@GenerateSpies` to forward to.
    private static let foreignParents: Set = [
        "Identifiable", "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable",
        "CustomStringConvertible", "CustomDebugStringConvertible", "Error", "LocalizedError",
        "Sequence", "Collection", "AsyncSequence", "RawRepresentable", "CaseIterable", "ObservableObject",
    ]

    /// The protocol as written.
    let declaration: ProtocolDeclSyntax
    /// Whether the protocol is declared inside another type, where an extension written at the
    /// top of the file can't see the types its requirements name.
    let isNested: Bool
    /// The protocol's access level, such as `public`; empty for the default.
    let access: String
    /// Whether the protocol inherits `Actor`, so its spy is an actor.
    let isActor: Bool
    /// Whether the protocol inherits `Sendable`.
    let isSendable: Bool
    /// The protocols it inherits that have requirements, whose spies its spy stores.
    let parents: [Parent]
    /// Each associated type's name and the constraints its generic parameter keeps.
    let associatedTypes: [(name: String, constraints: [String])]
    /// The requirements the protocol declares itself, each of which gets a spy.
    let requirements: [any Requirement]
    /// The name of each requirement's spy, in the order of `requirements`.
    let spyNames: [String]

    /// The protocol's name.
    var name: String {
        declaration.name.text
    }

    /// The spy class's name.
    var spyName: String {
        name + spySuffix
    }

    /// The access level the generated code is written with, followed by a space when there is one.
    var prefix: String {
        access.isEmpty ? "" : access + " "
    }

    /// The protocol's global actor attributes, such as `@MainActor`, one per line.
    var actors: String {
        declaration.attributes.globalActors
            .map { $0.trimmedDescription + "\n" }
            .joined()
    }

    /// The spy's generic parameters, one per associated type, such as `<Item: Equatable>`; empty
    /// when the protocol has none.
    var genericParameters: String {
        guard !associatedTypes.isEmpty else {
            return ""
        }
        let parameters = associatedTypes.map { associated in
            associated.constraints.isEmpty
                ? associated.name
                : associated.name + ": " + associated.constraints.joined(separator: " & ")
        }
        return "<" + parameters.joined(separator: ", ") + ">"
    }

    /// This protocol as a parent: the spy that a child's spy stores for it.
    var own: Parent {
        Parent(type: name, label: Self.initializerLabel(for: name))
    }

    /// Why this protocol's requirements can't be forwarded to its spy; `nil` when they can.
    var whyNotForwarded: String? {
        if isActor {
            return "is an actor protocol"
        }
        if isNested {
            return "is declared inside another type"
        }
        if requirements.contains(where: { $0 is InitializerRequirement }) {
            return "declares an init"
        }
        return associatedTypes.isEmpty ? nil : "has associated types"
    }

    /// Reads a protocol, or explains why its spy can't be written.
    init(_ declaration: ProtocolDeclSyntax, isNested: Bool) throws {
        self.declaration = declaration
        self.isNested = isNested
        access = GenerateSpiesMacro.access(of: declaration.modifiers)
        let inherited = declaration.inheritanceClause?.inheritedTypes.map(\.type) ?? []
        let written = inherited.map(\.trimmedDescription)
        isActor = written.contains { $0 == "Actor" || $0 == "_Concurrency.Actor" }
        isSendable = written.contains { $0 == "Sendable" || $0 == "Swift.Sendable" }
        parents = try Self.parents(of: declaration, among: inherited, isActor: isActor)
        // An actor is Sendable, so its spy's nonisolated spies need Sendable values too.
        associatedTypes = try Self.associatedTypes(of: declaration, isSendable: isSendable || isActor)
        let declared = try declaration.memberBlock.members.compactMap { member in
            try Self.requirement(member.decl, in: declaration)
        }
        let names = try UnderstudyMacros.spyNames(for: declared)
        requirements = try Self.settingInitializers(
            of: declared,
            named: names,
            in: declaration,
            isActor: isActor,
            parents: parents
        )
        spyNames = names
        if !associatedTypes.isEmpty, let shared = requirements.first(where: \.isStatic) {
            throw UnderstudyError(
                "'\(shared.baseName)' is static, and a spy with associated types is generic, so it can't "
                    + "keep a static spy; use @GenerateSpies on a class or an actor that conforms to "
                    + "'\(declaration.name.text)' instead",
                at: shared.nameToken
            )
        }
    }

    /// The protocols `declaration` inherits that have requirements, each with the label its spy
    /// takes in the child spy's initializer. Refuses the ones the macro can't forward to.
    private static func parents(
        of declaration: ProtocolDeclSyntax,
        among inherited: [TypeSyntax],
        isActor: Bool
    ) throws -> [Parent] {
        let name = declaration.name.text
        let classForm = "use @GenerateSpies on a class or an actor that conforms to '\(name)' instead"
        return try inherited.filter { !markers.contains($0.trimmedDescription) }.map { parent in
            let written = parent.trimmedDescription
            if isActor {
                throw UnderstudyError(
                    "'\(name)' is an actor protocol that inherits '\(written)', which its spy can't "
                        + "forward to across the actor; \(classForm)",
                    at: parent
                )
            }
            if foreignParents.contains(written) || written.hasPrefix("Swift.") || written.hasPrefix("Foundation.") {
                throw UnderstudyError(
                    "'\(name)' inherits '\(written)', which has no spy to forward to; \(classForm)",
                    at: parent
                )
            }
            if written.contains("<") {
                throw UnderstudyError(
                    "'\(name)' inherits '\(written)', which has associated types, so its spy can't "
                        + "forward to that one's spy; \(classForm)",
                    at: parent
                )
            }
            return Parent(type: written, label: initializerLabel(for: written))
        }
    }

    /// The label a parent's spy takes in the child spy's initializer: the parent's name with its
    /// leading capitals in lower case, as Swift names a value of a type, such as `base` for
    /// `Base`, `urlLoader` for `URLLoader` and `accountBase` for `Account.Base`.
    private static func initializerLabel(for parent: String) -> String {
        let name = parent.split(separator: ".").map(String.init).joined()
        let capitals = name.prefix { $0.isUppercase }
        let lowered = capitals.count > 1 && capitals.count < name.count ? capitals.dropLast() : capitals
        return lowered.lowercased() + name.dropFirst(lowered.count)
    }

    /// Each associated type, with the constraints its generic parameter keeps, and `Sendable`
    /// when the protocol is, or is an actor protocol, because the spy stores values of it.
    /// Refuses a `where` clause, on the protocol or on an associated type.
    private static func associatedTypes(
        of declaration: ProtocolDeclSyntax,
        isSendable: Bool
    ) throws -> [(name: String, constraints: [String])] {
        let declared = declaration.memberBlock.members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self) }
        if let clause = declaration.genericWhereClause, !declared.isEmpty {
            throw UnderstudyError(
                "'\(declaration.name.text)' has a where clause, which the spy's generic parameters can't "
                    + "keep; use @GenerateSpies on a class or an actor that conforms to "
                    + "'\(declaration.name.text)' instead",
                at: clause
            )
        }
        return try declared.map { associated in
            if associated.genericWhereClause != nil {
                throw UnderstudyError(
                    "'\(associated.name.text)' has a where clause, which a generic parameter can't keep; "
                        + "use @GenerateSpies on a class or an actor that conforms to "
                        + "'\(declaration.name.text)' instead",
                    at: associated.name
                )
            }
            // `var` because `Sendable` joins the written constraints for a `Sendable` protocol.
            var constraints = associated.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
            if isSendable, !constraints.contains(where: { $0 == "Sendable" || $0 == "Swift.Sendable" }) {
                constraints.append(GeneratedName.sendable)
            }
            return (associated.name.text, constraints)
        }
    }

    /// The requirement a member declares; `nil` for an associated type, which becomes a generic
    /// parameter instead.
    private static func requirement(
        _ member: DeclSyntax,
        in declaration: ProtocolDeclSyntax
    ) throws -> (any Requirement)? {
        if let function = member.as(FunctionDeclSyntax.self) {
            return try FunctionRequirement(function)
        }
        if let property = member.as(VariableDeclSyntax.self) {
            return try PropertyRequirement(property, inProtocol: true)
        }
        if let spied = member.as(SubscriptDeclSyntax.self) {
            return try SubscriptRequirement(spied, inProtocol: true)
        }
        if let initializer = member.as(InitializerDeclSyntax.self) {
            return try InitializerRequirement(initializer)
        }
        if member.is(AssociatedTypeDeclSyntax.self) {
            return nil
        }
        throw UnderstudyError(
            "'\(declaration.name.text)' has a requirement that is not a function, a property, a "
                + "subscript or an init; write its double by hand, or use @GenerateSpies on a class or an actor",
            at: member
        )
    }
}
