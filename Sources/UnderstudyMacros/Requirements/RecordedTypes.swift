//
//  RecordedTypes.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

extension FunctionRequirement {
    /// A type with a generic parameter in it, as its spy records it.
    struct Erased {
        /// The type the spy records, such as `[any Tag]` for `[T]`.
        let type: String
        /// The generic parameter's name, such as `T`.
        let parameter: String
    }

    /// Each generic parameter's name, and the type its spy records it as: `any` of its constraints,
    /// or `Any` when it has none. Refuses what a spy can't record: a `where` clause or a pack.
    static func erasedGenerics(of declaration: FunctionDeclSyntax, in where_: String) throws -> [String: String] {
        guard let clause = declaration.genericParameterClause else {
            return [:]
        }
        if declaration.genericWhereClause != nil || clause.genericWhereClause != nil {
            throw UnderstudyError("\(where_) has a where clause; write its double by hand", at: declaration.name)
        }
        var generics: [String: String] = [:]
        for parameter in clause.parameters {
            if parameter.specifier != nil {
                let message = "\(where_) takes a parameter pack; write its double by hand"
                throw UnderstudyError(message, at: declaration.name)
            }
            generics[parameter.name.text] = parameter.inheritedType.map { "any " + $0.trimmedDescription } ?? "Any"
        }
        return generics
    }

    /// The type a spy records for a type that is a generic parameter, or an array, an optional, a
    /// dictionary's value or a set of one, with that parameter's name; `nil` for any other type.
    /// A set is recorded as `Set<AnyHashable>`, because `any` of a protocol isn't `Hashable`.
    static func erased(_ type: TypeSyntax, generics: [String: String]) -> Erased? {
        func generic(_ element: some SyntaxProtocol) -> Erased? {
            let name = element.trimmedDescription
            return generics[name].map { Erased(type: $0, parameter: name) }
        }
        if let whole = generic(type) {
            return whole
        }
        if let array = type.as(ArrayTypeSyntax.self), let element = generic(array.element) {
            return Erased(type: "[\(element.type)]", parameter: element.parameter)
        }
        if let optional = type.as(OptionalTypeSyntax.self), let wrapped = generic(optional.wrappedType) {
            return Erased(type: "(\(wrapped.type))?", parameter: wrapped.parameter)
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self), !mentionsGeneric(dictionary.key, generics),
           let value = generic(dictionary.value) {
            return Erased(type: "[\(dictionary.key.trimmedDescription): \(value.type)]", parameter: value.parameter)
        }
        if let set = type.as(IdentifierTypeSyntax.self), set.name.text == "Set",
           let arguments = set.genericArgumentClause?.arguments, arguments.count == 1,
           let element = arguments.first.flatMap({ generic($0.argument) }) {
            return Erased(type: "Swift.Set<Swift.AnyHashable>", parameter: element.parameter)
        }
        return nil
    }

    /// Whether a type mentions a generic parameter anywhere in it.
    private static func mentionsGeneric(_ type: some SyntaxProtocol, _ generics: [String: String]) -> Bool {
        type.tokens(viewMode: .sourceAccurate).contains { generics[$0.text] != nil }
    }

    /// Refuses a type that mentions a generic parameter without being it.
    static func refuseNested(_ type: some SyntaxProtocol, generics: [String: String], in where_: String) throws {
        if let name = type.tokens(viewMode: .sourceAccurate).first(where: { generics[$0.text] != nil })?.text {
            throw UnderstudyError(
                "\(where_) uses '\(name)' inside another type; write its double by hand",
                at: type
            )
        }
    }

    /// The type a spy records for a parameter: `@escaping` dropped, `some` turned into `any`, a
    /// generic parameter as the type ``erasedGenerics(of:in:)`` gives it, and a variadic parameter
    /// as an array.
    static func storedType(
        of parameter: FunctionParameterSyntax,
        generics: [String: String],
        in where_: String
    ) throws -> String {
        var type = parameter.type
        if let attributed = type.as(AttributedTypeSyntax.self) {
            if attributed.specifiers.contains(where: { $0.trimmedDescription.hasPrefix("inout") }) {
                throw UnderstudyError("\(where_) takes an inout parameter; write its double by hand", at: parameter)
            }
            let kept = attributed.attributes.filter { attribute in
                let name = attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription
                if name == "autoclosure" {
                    return true
                }
                return name != "escaping"
            }
            let isAutoclosure = kept.contains { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "autoclosure"
            }
            if isAutoclosure {
                throw UnderstudyError("\(where_) takes an autoclosure; write its double by hand", at: parameter)
            }
            type = TypeSyntax(attributed.with(\.attributes, kept))
        }
        var text = type.trimmedDescription
        if let erased = erased(type, generics: generics) {
            text = erased.type
        } else {
            try refuseNested(type, generics: generics, in: where_)
        }
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self), someOrAny.someOrAnySpecifier.text == "some" {
            text = "any " + someOrAny.constraint.trimmedDescription
        }
        if parameter.ellipsis != nil {
            text = "[\(text)]"
        }
        return text
    }
}
