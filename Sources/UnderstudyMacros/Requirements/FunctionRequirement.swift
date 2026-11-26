//
//  FunctionRequirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// One function requirement a double stands in for, read from its declaration.
///
/// - `Requirement`: the macros write its spy, forwarder and body like any other requirement's.
struct FunctionRequirement: Requirement {
    /// One parameter: the name the body uses and the type the spy records.
    struct Parameter {
        /// The name the body passes it by.
        let name: String
        /// The type the spy records it as.
        let type: String
        /// Whether the requirement takes it `@escaping`; the forwarder must too, to pass it on.
        let escapes: Bool
    }

    /// The requirement as written.
    let declaration: FunctionDeclSyntax
    /// Whether it is `static` or `class`.
    let isStatic: Bool
    /// The argument labels, `_` for none.
    let labels: [String]
    /// Its parameters, as the spy records them.
    let parameters: [Parameter]
    /// Whether it throws, so its spy is a `ThrowingSpy`.
    let throwsError: Bool
    /// The error type a typed `throws` names, such as `AuthError`, which the body rethrows the
    /// spy's error as; `nil` for a plain `throws`, `throws(any Error)` or no `throws`.
    let typedError: String?
    /// Whether it is async, so the body goes through `respond(to:)`.
    let isAsync: Bool
    /// The type the spy answers with.
    let output: String
    /// The return type as written, which ``obviousAnswer`` reads; `nil` when it returns nothing.
    let returnType: TypeSyntax?
    /// Whether it returns nothing, so the spy answers `()`.
    let returnsNothing: Bool
    /// Whether it returns an optional, so the spy can start with `nil`.
    let returnsOptional: Bool
    /// Whether the answer is a closure, which the double's initializer must take `@escaping`.
    let returnsFunction: Bool
    /// The type the body casts the answer back to when the requirement returns a generic
    /// parameter, or an array, a dictionary or a set of one, such as `T` or `[T]` (`T` for `T?`);
    /// `nil` when it returns none.
    let returnedGeneric: String?
    /// The generic parameter in ``returnedGeneric``, which the forwarder keeps generic.
    let returnedParameter: String?

    /// The spy's input type: nothing, the one parameter's type, or a labelled tuple of them all.
    var input: String {
        switch parameters.count {
        case 0:
            return GeneratedName.void
        case 1:
            return parameters[0].type
        default:
            return "(" + parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }

    /// The spy's type.
    var spyType: String {
        let kind = throwsError ? GeneratedName.throwingSpy : GeneratedName.spy
        return "\(kind)<\(input), \(output)>"
    }

    /// The function's name.
    var nameToken: TokenSyntax {
        declaration.name
    }

    /// An answer is needed unless it returns nothing or an optional.
    var needsAnswer: Bool {
        !returnsNothing && !returnsOptional
    }

    /// `()` when it returns nothing, otherwise `nil`.
    var defaultAnswer: String {
        returnsNothing ? "()" : "nil"
    }

    /// The output, `@escaping` when it is a closure.
    var answerType: String {
        (returnsFunction ? "@escaping " : "") + output
    }

    /// The obvious value of the return type, when it has one.
    var obviousAnswer: String? {
        returnType.flatMap(obviousDefault(of:))
    }

    /// The name of the private function `@GenerateSpies` writes for this requirement on a class.
    /// The requirement's body calls it with its own labels, so overloads reach their own spy.
    var forwarderName: String {
        "__understudy_" + baseName
    }

    /// The parameters of the forwarder, with the requirement's labels and the spy's types.
    var forwarderParameters: String {
        zip(labels, parameters).map { label, parameter in
            let names = label == parameter.name ? label : "\(label) \(parameter.name)"
            let escaping = parameter.escapes ? "@escaping " : ""
            return "\(names): \(escaping)\(parameter.type)"
        }.joined(separator: ", ")
    }

    /// The arguments the requirement's body passes to its forwarder.
    var forwarderArguments: String {
        zip(labels, parameters).map { label, parameter in
            label == "_" ? parameter.name : "\(label): \(parameter.name)"
        }.joined(separator: ", ")
    }

    /// The argument the body passes to the spy.
    var callArgument: String {
        switch parameters.count {
        case 0:
            return ""
        case 1:
            return parameters[0].name
        default:
            return "(" + parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ") + ")"
        }
    }

    /// Reads a requirement, or explains why it can't be written.
    init(_ declaration: FunctionDeclSyntax) throws {
        self.declaration = declaration
        let subject = "'\(declaration.name.text)'"
        let generics = try Self.erasedGenerics(of: declaration, in: subject)
        isStatic = try Self.isStatic(declaration, in: subject)
        let effects = try Effects(of: declaration, generics: generics, in: subject)
        throwsError = effects.throwsError
        typedError = effects.typedError
        isAsync = effects.isAsync
        let parameterList = declaration.signature.parameterClause.parameters
        labels = parameterList.map(\.firstName.text)
        parameters = try parameterList.map { parameter in
            try Self.parameter(parameter, generics: generics, in: subject)
        }
        returnType = declaration.signature.returnClause?.type
        let returned = try Returned(returnType, generics: generics, in: subject, at: declaration.name)
        output = returned.output
        returnedGeneric = returned.generic
        returnedParameter = returned.parameter
        returnsNothing = returned.isNothing
        returnsOptional = returned.isOptional
        returnsFunction = returned.isFunction
    }

    /// Whether a type is optional: `T?`, `T!` or `Optional<T>`, so `nil` is a fine first answer.
    static func isOptional(_ type: TypeSyntax) -> Bool {
        type.is(OptionalTypeSyntax.self)
            || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || type.trimmedDescription.hasPrefix("Optional<")
    }

    /// Whether a type is a closure, such as `() -> Void`, `@Sendable () -> Void` or `(() -> Void)`.
    static func isFunction(_ type: TypeSyntax) -> Bool {
        if type.is(FunctionTypeSyntax.self) {
            return true
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunction(attributed.baseType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
            let only = tuple.elements.first, only.firstName == nil
        {
            return isFunction(only.type)
        }
        return false
    }

    /// The statements that call `spy` and return its answer, cast back to the generic parameter
    /// the requirement returns, with the spy's error rethrown as the typed `throws` names. A
    /// wrong-typed answer or error stops the test, naming the spy and both types.
    func body(on spy: String) -> String {
        guard let typedError else {
            return answer(on: spy)
        }
        let wrongType =
            "\(GeneratedName.fatalError)(\"@GenerateSpies: \(spy) threw "
            + "\\(Swift.type(of: error)), not \\(\(typedError).self)\")"
        return """
            do {
            \(answer(on: spy))
            } catch let error as \(typedError) {
            throw error
            } catch {
            \(wrongType)
            }
            """
    }

    /// The statements that call `spy` and return its answer, cast back to the generic parameter
    /// the requirement returns. A wrong-typed answer stops the test, naming the spy and both types.
    private func answer(on spy: String) -> String {
        guard let generic = returnedGeneric else {
            return "return " + call(on: spy)
        }
        let answer = "__understudy_answer"
        let wrongType =
            "\(GeneratedName.fatalError)(\"@GenerateSpies: \(spy) answered "
            + "\\(Swift.type(of: \(answer))), not \\(\(generic).self)\")"
        let fetch =
            returnsOptional
            ? "guard let \(answer) = \(call(on: spy)) else {\nreturn nil\n}"
            : "let \(answer) = \(call(on: spy))"
        return """
            \(fetch)
            guard let typed = \(answer) as? \(generic) else {
            \(wrongType)
            }
            return typed
            """
    }

    /// The call that records the input and gives the answer: through `respond(to:)` when the
    /// requirement is async, so the test can hold the call.
    func call(on spy: String) -> String {
        let attempt = throwsError ? "try " : ""
        guard isAsync else {
            return "\(attempt)self.\(spy)(\(callArgument))"
        }
        let input = parameters.isEmpty ? "()" : callArgument
        return "\(attempt)await self.\(spy).respond(to: \(input))"
    }
}
