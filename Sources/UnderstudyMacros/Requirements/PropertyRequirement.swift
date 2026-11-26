//
//  PropertyRequirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// One property requirement a double stands in for, read from its declaration: a
/// `@SpiedProperty var` with a type and nothing else on a class, or a `var` requirement of a
/// protocol.
///
/// - `Requirement`: the macros write its spy and accessors like any other requirement's.
struct PropertyRequirement: Requirement {
    /// The property's name.
    let nameToken: TokenSyntax
    /// Whether it is `static` or `class`.
    let isStatic: Bool
    /// The property's type, which the spy keeps.
    let type: String
    /// The type as written, which ``obviousAnswer`` reads.
    let typeSyntax: TypeSyntax
    /// Whether the type is optional, so the spy can start with `nil`.
    let isOptional: Bool
    /// Whether the type is a closure, which the initializer takes `@escaping`.
    let isFunction: Bool
    /// The first value written at the declaration, such as `"ana"`, which the spy starts with.
    let initialValue: String?

    /// None: a property has no overloads.
    var labels: [String] {
        []
    }

    /// A `PropertySpy` of the property's type.
    var spyType: String {
        "\(GeneratedName.propertySpy)<\(type)>"
    }

    /// A first value is needed unless the type is optional or the declaration gives one.
    var needsAnswer: Bool {
        !isOptional && initialValue == nil
    }

    /// The declaration's first value, otherwise `nil`.
    var defaultAnswer: String {
        initialValue ?? "nil"
    }

    /// The type, `@escaping` when it is a closure.
    var answerType: String {
        (isFunction ? "@escaping " : "") + type
    }

    /// The obvious value of the type, when it has one.
    var obviousAnswer: String? {
        obviousDefault(of: typeSyntax)
    }

    /// The private property `@GenerateSpies` writes for this property on a class, which the
    /// accessors `@Spied` writes go through.
    var forwarderName: String {
        "__understudy_property_" + nameToken.text
    }

    /// Reads a property, or explains why it can't be written. On a class it must have no
    /// accessors, and may have a first value; a protocol's always has accessors.
    init(_ declaration: VariableDeclSyntax, inProtocol: Bool) throws {
        guard declaration.bindings.count == 1, let binding = declaration.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw UnderstudyError("declare one property at a time", at: declaration.bindings)
        }
        nameToken = pattern.identifier
        let where_ = "'\(pattern.identifier.text)'"
        let modifiers = declaration.modifiers.map(\.name.text)
        isStatic = modifiers.contains("static") || modifiers.contains("class")
        try Self.refuseLet(declaration, named: pattern.identifier, in: where_)
        let annotation = try Self.typeAnnotation(of: binding, named: pattern.identifier, in: where_)
        initialValue = binding.initializer?.value.trimmedDescription
        if !inProtocol, binding.accessorBlock != nil {
            throw UnderstudyError("\(where_) is @SpiedProperty, so give it no accessors", at: pattern.identifier)
        }
        let type = annotation.type
        typeSyntax = type
        self.type = type.trimmedDescription
        isOptional = FunctionRequirement.isOptional(type)
        isFunction = FunctionRequirement.isFunction(type)
    }

    /// Refuses a `let`, which a spy can't set, with a fix-it that makes it a `var`.
    private static func refuseLet(
        _ declaration: VariableDeclSyntax,
        named name: TokenSyntax,
        in where_: String
    ) throws {
        guard declaration.bindingSpecifier.tokenKind == .keyword(.let) else {
            return
        }
        throw UnderstudyError(
            "\(where_) is a let; declare it as a var",
            at: name,
            fixIt: .replace(
                message: UnderstudyFixIt("Replace 'let' with 'var'"),
                oldNode: declaration.bindingSpecifier,
                newNode: TokenSyntax.keyword(.var, trailingTrivia: .space)
            )
        )
    }

    /// The property's written type. Refuses a property with none, with a fix-it that adds a
    /// placeholder for it.
    private static func typeAnnotation(
        of binding: PatternBindingSyntax,
        named name: TokenSyntax,
        in where_: String
    ) throws -> TypeAnnotationSyntax {
        if let annotation = binding.typeAnnotation {
            return annotation
        }
        // The type takes the space the name had before an initializer: `token = 0` becomes
        // `token: <#Type#> = 0`.
        let placeholder = TypeSyntax("<#Type#>").with(\.leadingTrivia, .space)
            .with(\.trailingTrivia, binding.pattern.trailingTrivia)
        let typed = binding.with(\.pattern, binding.pattern.trimmed)
            .with(\.typeAnnotation, TypeAnnotationSyntax(type: placeholder))
        throw UnderstudyError(
            "\(where_) has no type; write its type",
            at: name,
            fixIt: .replace(message: UnderstudyFixIt("Add a type"), oldNode: binding, newNode: typed)
        )
    }
}
