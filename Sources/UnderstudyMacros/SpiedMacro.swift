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
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw UnderstudyError("@Spied goes on a function")
        }
        guard isInsideUnderstudyType(context) else {
            throw UnderstudyError("@Spied needs @GenerateSpies on the class or actor it is in")
        }
        // `@GenerateSpies` explains a requirement it can't write, at the requirement. The body only has
        // to compile until the person fixes it.
        guard let requirement = try? Requirement(function) else {
            return ["fatalError(\"@GenerateSpies can't write this requirement\")"]
        }
        let attempt = requirement.throwsError ? "try " : ""
        let wait = requirement.isAsync ? "await " : ""
        let call = "\(requirement.forwarderName)(\(requirement.forwarderArguments))"
        return ["return \(raw: attempt)\(raw: wait)self.\(raw: call)"]
    }

    /// Whether the declaration is a member of a class or an actor marked `@GenerateSpies`.
    static func isInsideUnderstudyType(_ context: some MacroExpansionContext) -> Bool {
        guard let type = context.lexicalContext.first,
              let attributes = type.as(ClassDeclSyntax.self)?.attributes ?? type.as(ActorDeclSyntax.self)?.attributes else {
            return false
        }
        return attributes.contains { element in
            let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
            return name == "GenerateSpies" || name == "Understudy.GenerateSpies"
        }
    }

    /// The statements that call a spy directly and return its answer, for the spy class
    /// `@GenerateSpies` writes next to a protocol.
    static func body(of requirement: Requirement, spy: String) -> CodeBlockItemListSyntax {
        "\(raw: requirement.body(on: spy))"
    }
}
