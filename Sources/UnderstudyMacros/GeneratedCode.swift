//
//  GeneratedCode.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax
import SwiftSyntaxMacros

extension Requirement {
    /// The private function a `@Spied` function's body calls on a class: it takes the function's
    /// labels, keeps its isolation and its effects, and calls `spy`.
    func forwarder(spy: String) -> DeclSyntax {
        let actors = declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }
            .filter { $0.attributeName.trimmedDescription.hasSuffix("Actor") }
            .map { $0.trimmedDescription + " " }
            .joined()
        let isolation = declaration.modifiers.contains { $0.name.text == "nonisolated" } ? "nonisolated " : ""
        let effects = (isAsync ? " async" : "") + (throwsError ? " throws" : "")
        let signature = "\(forwarderName)(\(forwarderParameters))\(effects)"
        return """
            \(raw: actors)private \(raw: isolation)func \(raw: signature) -> \(raw: output) {
            return \(raw: call(on: spy))
            }
            """
    }

    /// The requirement with a body that calls `spy`, for the spy class written next to a protocol.
    func implementation(spy: String, access: String) -> DeclSyntax {
        var function = declaration
        function.body = CodeBlockSyntax(statements: SpiedMacro.body(of: self, spy: spy))
        function.leadingTrivia = []
        if !access.isEmpty {
            function.modifiers.append(DeclModifierSyntax(name: .identifier(access), trailingTrivia: .space))
        }
        return DeclSyntax(function)
    }
}

extension Property {
    /// The private property a `@SpiedProperty` property's accessors go through on a class.
    func forwarder(spy: String) -> DeclSyntax {
        "private var \(raw: forwarderName): \(raw: spyType) { self.\(raw: spy) }"
    }

    /// The property with accessors that go through `spy`, for the spy class written next to a
    /// protocol.
    func implementation(spy: String, access: String) -> DeclSyntax {
        let prefix = access.isEmpty ? "" : access + " "
        let accessors = SpiedPropertyMacro.accessors(spy: "self." + spy).map(\.description).joined(separator: "\n")
        return """
            \(raw: prefix)var \(raw: baseName): \(raw: type) {
            \(raw: accessors)
            }
            """
    }
}
