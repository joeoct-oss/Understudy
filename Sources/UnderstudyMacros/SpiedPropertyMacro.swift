//
//  SpiedPropertyMacro.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// `@SpiedProperty`: writes the getter and setter of a `var` declared with a type and nothing else
/// in a `@GenerateSpies` class. They go through the private forwarder `@GenerateSpies` wrote for the
/// property, to its ``PropertySpy``.
public struct SpiedPropertyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            throw UnderstudyError("@SpiedProperty goes on a var")
        }
        guard SpiedMacro.isInsideUnderstudyType(context) else {
            throw UnderstudyError("@SpiedProperty needs @GenerateSpies on the class or actor it is in")
        }
        // `@GenerateSpies` explains a property it can't write, at the property.
        guard let property = try? Property(variable, inProtocol: false) else {
            return []
        }
        return accessors(spy: "self." + property.forwarderName)
    }

    /// A property's getter and setter, which go through `spy`.
    static func accessors(spy: String) -> [AccessorDeclSyntax] {
        [
            "get { \(raw: spy).get() }",
            "set { \(raw: spy).set(newValue) }",
        ]
    }
}
