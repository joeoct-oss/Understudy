//
//  SampleParameter.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// One parameter of `sample(...)`: a property the memberwise initializer takes, with its default.
struct SampleParameter {
    /// The default of every type that has a fixed one, by the name the struct writes it with.
    private static let fixedDefaults: [String: String] = {
        var defaults = [
            "String": #""""#,
            "Substring": #""""#,
            "Bool": "false",
            "Date": "Date(timeIntervalSince1970: 0)",
            "UUID": #"UUID(uuidString: "00000000-0000-0000-0000-000000000000")!"#,
            "URL": #"URL(string: "https://example.com")!"#,
        ]
        let numbers = [
            "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "CGFloat", "Decimal",
        ]
        for number in numbers {
            defaults[number] = "0"
        }
        return defaults
    }()

    let name: String
    let type: String
    let value: String

    /// The parameters a `var` or `let` declaration gives. A static or computed property and a `let`
    /// that has its value give none, because the memberwise initializer doesn't take them. A lazy
    /// one gives none either: it keeps its own first value.
    static func parameters(of variable: VariableDeclSyntax) throws -> [SampleParameter] {
        let leftOut = variable.modifiers.contains { ["static", "class", "lazy"].contains($0.name.text) }
        let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
        guard !leftOut else {
            return []
        }
        let chosen = chosenDefault(of: variable)
        return try variable.bindings.compactMap { binding in
            guard isStored(binding), !(isLet && binding.initializer != nil) else {
                return nil
            }
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                throw SampleError(
                    "declare each property on its own, such as 'let x: Int', so each gets its own "
                        + "sample(...) parameter",
                    at: binding.pattern
                )
            }
            let name = pattern.identifier.text
            guard let type = binding.typeAnnotation?.type else {
                throw SampleError("give '\(name)' a type, because its sample(...) parameter needs one", at: binding)
            }
            let value = chosen ?? binding.initializer?.value.trimmedDescription ?? defaultValue(of: type)
            return SampleParameter(name: name, type: type.trimmedDescription, value: value)
        }
    }

    /// Whether a property is stored: it has no accessors, or only `willSet` and `didSet`.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        switch binding.accessorBlock?.accessors {
        case .none:
            return true
        case .accessors(let accessors):
            return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        case .getter:
            return false
        }
    }

    /// The value of `@SampleDefault(...)` on a property, if it has one.
    private static func chosenDefault(of variable: VariableDeclSyntax) -> String? {
        let attribute = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }.first { attribute in
            let name = attribute.attributeName.trimmedDescription
            return name == "SampleDefault" || name == "UnderstudySamples.SampleDefault"
        }
        return attribute?.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription
    }

    /// The default of a type: `nil` for an optional, an empty collection, a fixed value for the
    /// types in `fixedDefaults`, and the type's own `.sample()` for any other, so a type with
    /// `@Sample` just works, and the compiler reports a type without one at this parameter.
    private static func defaultValue(of type: TypeSyntax) -> String {
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return "nil"
        }
        if type.is(ArrayTypeSyntax.self) {
            return "[]"
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "[:]"
        }
        let name = type.as(IdentifierTypeSyntax.self)?.name.text ?? ""
        switch name {
        case "Optional":
            return "nil"
        case "Array", "Set":
            return "[]"
        case "Dictionary":
            return "[:]"
        default:
            return fixedDefaults[name] ?? ".sample()"
        }
    }
}
