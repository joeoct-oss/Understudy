//
//  FunctionSignature.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

extension FunctionRequirement {
    /// What a function's signature says it does besides answering: whether it is async, and
    /// whether and what it throws.
    struct Effects {
        /// The ways to write a typed `throws` that is a plain `throws`.
        private static let untypedErrors = ["any Error", "Error", "any Swift.Error", "Swift.Error"]

        /// Whether it throws.
        let throwsError: Bool
        /// The error type a typed `throws` names; `nil` for a plain `throws` or none.
        let typedError: String?
        /// Whether it is async.
        let isAsync: Bool

        /// Reads the effects of `signature`, the signature of `name`, or explains why a spy can't
        /// have them: `rethrows`, or a `throws` of one of its generic parameters.
        init(
            of signature: FunctionSignatureSyntax,
            named name: TokenSyntax,
            generics: [String: String],
            in subject: String
        ) throws {
            let effects = signature.effectSpecifiers
            let throwsClause = effects?.throwsClause
            if throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows) {
                throw UnderstudyError("\(subject) rethrows; write its double by hand", at: name)
            }
            let thrown = throwsClause?.type
            if let thrown,
                let name = thrown.tokens(viewMode: .sourceAccurate).first(where: { generics[$0.text] != nil })
            {
                throw UnderstudyError(
                    "\(subject) throws its generic parameter '\(name.text)'; write its double by hand",
                    at: thrown
                )
            }
            let thrownName = thrown?.trimmedDescription
            // `throws(Never)` throws nothing, and `throws(any Error)` is a plain `throws`.
            throwsError = throwsClause != nil && thrownName != "Never"
            if throwsError, let thrownName, !Self.untypedErrors.contains(thrownName) {
                typedError = thrownName
            } else {
                typedError = nil
            }
            isAsync = effects?.asyncSpecifier != nil
        }
    }

    /// What a function returns, as its spy answers it.
    struct Returned {
        /// The spy's output type.
        let output: String
        /// The type the body casts the answer back to, when it returns a generic parameter.
        let generic: String?
        /// The generic parameter in ``generic``.
        let parameter: String?
        /// Whether it returns nothing.
        let isNothing: Bool
        /// Whether it returns an optional.
        let isOptional: Bool
        /// Whether the answer is a closure.
        let isFunction: Bool

        /// Reads `returnType`, or explains why a spy can't answer it: an opaque type, or a type
        /// that holds a generic parameter the spy can't record. `name` is where errors point.
        init(
            _ returnType: TypeSyntax?,
            generics: [String: String],
            in subject: String,
            at name: TokenSyntax
        ) throws {
            guard let returnType else {
                self.init(output: GeneratedName.void, isNothing: true)
                return
            }
            let unwrapped = returnType.as(OptionalTypeSyntax.self)?.wrappedType ?? returnType
            if let erased = FunctionRequirement.erased(unwrapped, generics: generics) {
                let optional = returnType.is(OptionalTypeSyntax.self)
                self.init(
                    output: optional ? "(\(erased.type))?" : erased.type,
                    generic: unwrapped.trimmedDescription,
                    parameter: erased.parameter,
                    isOptional: optional
                )
                return
            }
            try FunctionRequirement.refuseNested(returnType, generics: generics, in: subject)
            let text = returnType.trimmedDescription
            if returnType.is(SomeOrAnyTypeSyntax.self), text.hasPrefix("some ") {
                throw UnderstudyError("\(subject) returns an opaque type; write its double by hand", at: name)
            }
            self.init(
                output: text,
                isNothing: text == "Void" || text == "()",
                isOptional: FunctionRequirement.isOptional(returnType),
                isFunction: FunctionRequirement.isFunction(returnType)
            )
        }

        /// A return with the values given, the others left as nothing special.
        private init(
            output: String,
            generic: String? = nil,
            parameter: String? = nil,
            isNothing: Bool = false,
            isOptional: Bool = false,
            isFunction: Bool = false
        ) {
            self.output = output
            self.generic = generic
            self.parameter = parameter
            self.isNothing = isNothing
            self.isOptional = isOptional
            self.isFunction = isFunction
        }
    }

    /// Whether `declaration` is `static` or `class`. Refuses a `mutating` one, which only a
    /// value type can have.
    static func isStatic(_ declaration: FunctionDeclSyntax, in subject: String) throws -> Bool {
        let modifiers = declaration.modifiers.map(\.name.text)
        if modifiers.contains("mutating") {
            throw UnderstudyError(
                "\(subject) is mutating; @GenerateSpies writes classes and actors",
                at: declaration.name
            )
        }
        return modifiers.contains("static") || modifiers.contains("class")
    }

    /// One parameter as the spy records it. Refuses one with no name, with a fix-it that adds one.
    static func parameter(
        _ parameter: FunctionParameterSyntax,
        generics: [String: String],
        in subject: String
    ) throws -> Parameter {
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else {
            throw UnderstudyError(
                "\(subject) has a parameter with no name; name it",
                at: parameter,
                fixIt: .replace(
                    message: UnderstudyFixIt("Add a name"),
                    oldNode: parameter,
                    newNode: named(parameter)
                )
            )
        }
        let escapes =
            parameter.type.as(AttributedTypeSyntax.self)?.attributes.contains { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "escaping"
            } ?? false
        return Parameter(
            name: name,
            type: try storedType(of: parameter, generics: generics, in: subject),
            escapes: escapes
        )
    }
}
