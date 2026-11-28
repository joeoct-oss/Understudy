//
//  SampleMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Sample`: writes `static func sample(...)` on a struct, inside `#if DEBUG`, with one parameter
/// per property the memberwise initializer takes, each with a default, and a body that calls that
/// initializer.
public struct SampleMacro: MemberMacro {
    /// The `sample(...)` function, inside `#if DEBUG`.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        do {
            return [try sample(of: declaration)]
        } catch let error as SampleError {
            // An error about a property is shown at the property, so the editor marks that line.
            context.diagnose(Diagnostic(node: error.node ?? Syntax(node), message: error))
            return []
        }
    }

    /// The `sample(...)` function of a struct, as visible as the struct.
    private static func sample(of declaration: some DeclGroupSyntax) throws -> DeclSyntax {
        guard let type = declaration.as(StructDeclSyntax.self) else {
            throw SampleError("attach it to a struct; only a struct has a memberwise initializer to call")
        }
        let parameters = try type.memberBlock.members
            .compactMap { member in member.decl.as(VariableDeclSyntax.self) }
            .flatMap(SampleParameter.parameters(of:))
        let access =
            type.modifiers
            .first { modifier in modifier.name.text == "public" || modifier.name.text == "package" }
            .map { modifier in modifier.name.text + " " } ?? ""
        let fields = parameters.map { parameter in "\(parameter.name): \(parameter.type) = \(parameter.value)" }
        let list = fields.joined(separator: ",\n")
        let arguments = parameters.map { parameter in "\(parameter.name): \(parameter.name)" }.joined(separator: ", ")
        return """
            #if DEBUG
            /// A complete value for tests, with a default for every property the test doesn't name.
            \(raw: access)static func sample(
            \(raw: list)
            ) -> Self {
            Self(\(raw: arguments))
            }
            #endif
            """
    }
}
