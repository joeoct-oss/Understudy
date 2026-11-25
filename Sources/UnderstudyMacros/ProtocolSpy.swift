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

    let declaration: ProtocolDeclSyntax
    /// Whether the protocol is declared inside another type, where an extension written at the
    /// top of the file can't see the types its requirements name.
    let isNested: Bool
    let access: String
    let isActor: Bool
    let isSendable: Bool
    let parents: [Parent]
    /// Each associated type's name and the constraints its generic parameter keeps.
    let associatedTypes: [(name: String, constraints: [String])]
    let requirements: [any SpiedMember]
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
        declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
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
        associatedTypes = try Self.associatedTypes(of: declaration, isSendable: isSendable)
        requirements = try declaration.memberBlock.members.compactMap { member in
            try Self.requirement(member.decl, in: declaration)
        }
        if !associatedTypes.isEmpty, let shared = requirements.first(where: \.isStatic) {
            throw UnderstudyError(
                "'\(shared.baseName)' is static, and a spy with associated types is generic, so it can't "
                    + "keep a static spy; use @GenerateSpies on a class or an actor that conforms to "
                    + "'\(declaration.name.text)' instead",
                at: shared.nameToken
            )
        }
        spyNames = try UnderstudyMacros.spyNames(for: requirements)
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
    /// when the protocol is, because the spy stores values of it. Refuses a `where` clause.
    private static func associatedTypes(
        of declaration: ProtocolDeclSyntax,
        isSendable: Bool
    ) throws -> [(name: String, constraints: [String])] {
        try declaration.memberBlock.members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self) }.map { associated in
            if associated.genericWhereClause != nil {
                throw UnderstudyError(
                    "'\(associated.name.text)' has a where clause, which a generic parameter can't keep; "
                        + "use @GenerateSpies on a class or an actor that conforms to "
                        + "'\(declaration.name.text)' instead",
                    at: associated.name
                )
            }
            var constraints = associated.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
            if isSendable, !constraints.contains(where: { $0 == "Sendable" || $0 == "Swift.Sendable" }) {
                constraints.append("Swift.Sendable")
            }
            return (associated.name.text, constraints)
        }
    }

    /// The requirement a member declares; `nil` for an associated type, which becomes a generic
    /// parameter instead.
    private static func requirement(
        _ member: DeclSyntax,
        in declaration: ProtocolDeclSyntax
    ) throws -> (any SpiedMember)? {
        if let function = member.as(FunctionDeclSyntax.self) {
            return try Requirement(function)
        }
        if let property = member.as(VariableDeclSyntax.self) {
            return try Property(property, inProtocol: true)
        }
        if let spied = member.as(SubscriptDeclSyntax.self) {
            return try Subscript(spied, inProtocol: true)
        }
        if member.is(AssociatedTypeDeclSyntax.self) {
            return nil
        }
        throw UnderstudyError(
            "'\(declaration.name.text)' has a requirement that is not a function, a property or a "
                + "subscript; write its double by hand, or use @GenerateSpies on a class or an actor",
            at: member
        )
    }

    /// The protocol a child protocol's spy adopts to forward this protocol's requirements to
    /// this protocol's spy. A protocol with associated types or an actor protocol can't be
    /// forwarded, so it gets one that is unavailable, whose message the child's spy shows.
    func forwardingProtocol() -> DeclSyntax {
        let forwarding = forwardingName(of: name)
        guard let why = whyNotForwarded else {
            let stored = own.property
            let inherited = ([name] + parents.map(\.forwarding) + ["AnyObject"]).joined(separator: ", ")
            return """
                /// Lets the spy of a protocol that inherits `\(raw: name)` answer its requirements
                /// through a `\(raw: spyName)`, written by `@GenerateSpies`.
                \(raw: actors)\(raw: prefix)protocol \(raw: forwarding): \(raw: inherited) {
                /// The spy that keeps the calls to `\(raw: name)`'s requirements.
                var \(raw: stored): \(raw: spyName) { get }
                }
                """
        }
        let message = "@GenerateSpies: '\(name)' \(why), so the spy of a protocol that inherits it can't "
            + "forward to its spy; use @GenerateSpies on a class or an actor that conforms to that protocol"
        return """
            /// Stands in for the forwarding protocol `\(raw: name)` can't have, so the spy of a
            /// protocol that inherits it explains why, written by `@GenerateSpies`.
            @available(*, unavailable, message: \(literal: message))
            \(raw: prefix)protocol \(raw: forwarding) { }
            """
    }

    /// This protocol as a parent: the spy that a child's spy stores for it.
    private var own: Parent {
        Parent(type: name, label: Self.initializerLabel(for: name))
    }

    /// Why this protocol's requirements can't be forwarded to its spy; `nil` when they can.
    private var whyNotForwarded: String? {
        if isActor {
            return "is an actor protocol"
        }
        if isNested {
            return "is declared inside another type"
        }
        return associatedTypes.isEmpty ? nil : "has associated types"
    }

    /// The extension that answers this protocol's requirements, for a type that adopts its
    /// forwarding protocol, through the spy it stores; `nil` when it can't be forwarded. It also
    /// reaches this protocol's parents' spies through it, so a grandchild's spy forwards too.
    func forwardingExtension() -> ExtensionDeclSyntax? {
        guard whyNotForwarded == nil else {
            return nil
        }
        let spies = zip(requirements, spyNames).flatMap { requirement, spy in
            forwardedSpies(of: requirement, named: spy, through: own)
        }
        let grandparents = parents.map { parent in
            "\(prefix)var \(parent.property): \(parent.spyType) { self.\(own.property).\(parent.property) }"
        }
        let implementations = zip(requirements, spyNames).map { requirement, spy in
            requirement.implementation(spy: spy, access: access).trimmedDescription
        }
        let body = (spies + grandparents + implementations).joined(separator: "\n\n")
        let source = """
            \(actors)extension \(name) where Self: \(own.forwarding) {
            \(body)
            }
            """
        return try? ExtensionDeclSyntax("\(raw: source)")
    }

    /// The computed properties that reach `requirement`'s spies in the stored parent spy, so a
    /// test reads them on the child's spy and the forwarded implementation calls them.
    private func forwardedSpies(of requirement: any SpiedMember, named spy: String, through own: Parent) -> [String] {
        let holder = requirement.isStatic ? own.spyType : "self." + own.property
        let keyword = requirement.isStatic ? "static var" : "var"
        let get = "\(prefix)\(keyword) \(spy): \(requirement.spyType) { \(holder).\(spy) }"
        guard let setSpyType = requirement.setSpyType else {
            return [get]
        }
        let setSpy = setSpyName(for: spy)
        return [get, "\(prefix)\(keyword) \(setSpy): \(setSpyType) { \(holder).\(setSpy) }"]
    }
}

/// The name of the protocol that forwards `protocol`'s requirements to its spy, such as
/// `BaseSpyForwarding` for `Base`.
func forwardingName(of protocol: String) -> String {
    `protocol` + spySuffix + "Forwarding"
}
