//
//  SpiedMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// `@Spied`: writes the body of a requirement declared with none in an `@Understudy` class. The body
/// calls the private forwarder `@Understudy` wrote for it, with the requirement's own labels, so an
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
        let requirement = try Requirement(function)
        let attempt = requirement.throwsError ? "try " : ""
        let call = "\(requirement.forwarderName)(\(requirement.forwarderArguments))"
        return ["return \(raw: attempt)self.\(raw: call)"]
    }

    /// The statements that call a spy directly and return its answer, for the spy class
    /// `@Understudy` writes next to a protocol.
    static func body(of requirement: Requirement, spy: String) -> CodeBlockItemListSyntax {
        let attempt = requirement.throwsError ? "try " : ""
        return "return \(raw: attempt)self.\(raw: spy)(\(raw: requirement.callArgument))"
    }
}
