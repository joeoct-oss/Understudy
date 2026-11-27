//
//  SpiedMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// `@Spied`: writes the body of a function declared with none in a `@GenerateSpies` class. The body
/// calls the private forwarder `@GenerateSpies` wrote for it, with the function's own labels, so an
/// overload reaches its own spy.
public struct SpiedMacro: BodyMacro {
    /// The body that calls the function's forwarder.
    public static func expansion(
        of _: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        if let accessor = declaration.as(AccessorDeclSyntax.self) {
            return try body(of: accessor, in: context)
        }
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw UnderstudyError("@Spied goes on a function, or on the get and set of a subscript")
        }
        guard isInsideUnderstudyType(context) else {
            throw UnderstudyError("@Spied needs @GenerateSpies on the class or actor it is in")
        }
        // `@GenerateSpies` explains a requirement it can't write, at the requirement. The body only
        // has to compile until the person fixes it.
        guard let requirement = try? FunctionRequirement(function) else {
            return ["\(raw: GeneratedName.fatalError)(\"@GenerateSpies can't write this requirement\")"]
        }
        let attempt = requirement.throwsError ? "try " : ""
        let wait = requirement.isAsync ? "await " : ""
        let call = "\(requirement.forwarderName)(\(requirement.forwarderArguments))"
        return ["return \(raw: attempt)\(raw: wait)self.\(raw: call)"]
    }

    /// The body of a subscript's `get` or `set` marked `@Spied`: it goes through the private
    /// subscript `@GenerateSpies` wrote for the subscript, so an overload reaches its own spies.
    private static func body(
        of accessor: AccessorDeclSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let declaration = context.lexicalContext.first?.as(SubscriptDeclSyntax.self) else {
            throw UnderstudyError("@Spied goes on a function, or on the get and set of a subscript")
        }
        guard isInsideUnderstudyType(context) else {
            throw UnderstudyError("@Spied needs @GenerateSpies on the class or actor it is in")
        }
        // `@GenerateSpies` explains a subscript it can't write, at the subscript. The context may
        // hold the subscript without its accessors, so only its indices are read here.
        guard let spied = try? SubscriptRequirement(declaration, checkingAccessors: false) else {
            return ["\(raw: GeneratedName.fatalError)(\"@GenerateSpies can't write this requirement\")"]
        }
        let target = spied.forwarderTarget
        guard accessor.accessorSpecifier.tokenKind == .keyword(.set) else {
            return ["return \(raw: target)"]
        }
        return ["\(raw: target) = newValue"]
    }

    /// Whether the declaration is a member of a class or an actor marked `@GenerateSpies`; for a
    /// subscript's `get` or `set`, the subscript's.
    static func isInsideUnderstudyType(_ context: some MacroExpansionContext) -> Bool {
        let contexts = context.lexicalContext.drop { $0.is(SubscriptDeclSyntax.self) }
        let type = contexts.first
        let attributes = type?.as(ClassDeclSyntax.self)?.attributes ?? type?.as(ActorDeclSyntax.self)?.attributes
        guard let attributes else {
            return false
        }
        return attributes.contains { element in
            let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
            return name == "GenerateSpies" || name == "Understudy.GenerateSpies"
        }
    }

    /// The statements that call a spy directly and return its answer, for the spy class
    /// `@GenerateSpies` writes next to a protocol.
    static func body(of requirement: FunctionRequirement, spy: String) -> CodeBlockItemListSyntax {
        "\(raw: requirement.body(on: spy))"
    }
}
