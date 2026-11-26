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
struct FunctionRequirement: Requirement {
    /// One parameter: the name the body uses and the type the spy records.
    struct Parameter {
        let name: String
        let type: String
        /// Whether the requirement takes it `@escaping`; the forwarder must too, to pass it on.
        let escapes: Bool
    }

    let declaration: FunctionDeclSyntax
    let isStatic: Bool
    let labels: [String]
    let parameters: [Parameter]
    let throwsError: Bool
    /// The error type a typed `throws` names, such as `AuthError`, which the body rethrows the
    /// spy's error as; `nil` for a plain `throws`, `throws(any Error)` or no `throws`.
    let typedError: String?
    let isAsync: Bool
    let output: String
    /// The return type as written, which ``obviousAnswer`` reads; `nil` when it returns nothing.
    let returnType: TypeSyntax?
    let returnsNothing: Bool
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
            return "Swift.Void"
        case 1:
            return parameters[0].type
        default:
            return "(" + parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }

    /// The spy's type.
    var spyType: String {
        let kind = throwsError ? "Understudy.ThrowingSpy" : "Understudy.Spy"
        return "\(kind)<\(input), \(output)>"
    }

    var nameToken: TokenSyntax {
        declaration.name
    }

    var needsAnswer: Bool {
        !returnsNothing && !returnsOptional
    }

    var defaultAnswer: String {
        returnsNothing ? "()" : "nil"
    }

    var answerType: String {
        (returnsFunction ? "@escaping " : "") + output
    }

    var obviousAnswer: String? {
        returnType.flatMap(obviousDefault(of:))
    }

    /// The statements that call `spy` and return its answer, cast back to the generic parameter
    /// the requirement returns, with the spy's error rethrown as the typed `throws` names. A
    /// wrong-typed answer or error stops the test, naming the spy and both types.
    func body(on spy: String) -> String {
        guard let typedError else {
            return answer(on: spy)
        }
        let wrongType =
            "Swift.fatalError(\"@GenerateSpies: \(spy) threw \\(Swift.type(of: error)), not \\(\(typedError).self)\")"
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
        let wrongType = "Swift.fatalError(\"@GenerateSpies: \(spy) answered "
            + "\\(Swift.type(of: \(answer))), not \\(\(generic).self)\")"
        let fetch = returnsOptional
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

    /// The name of the private function `@GenerateSpies` writes for this requirement on a class. The
    /// requirement's body calls it with its own labels, so overloads reach their own spy.
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
        let where_ = "'\(declaration.name.text)'"
        let generics = try Self.erasedGenerics(of: declaration, in: where_)
        let modifiers = declaration.modifiers.map(\.name.text)
        isStatic = modifiers.contains("static") || modifiers.contains("class")
        if modifiers.contains("mutating") {
            throw UnderstudyError(
                "\(where_) is mutating; @GenerateSpies writes classes and actors",
                at: declaration.name
            )
        }
        let signature = declaration.signature
        let throwsClause = signature.effectSpecifiers?.throwsClause
        if throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows) {
            throw UnderstudyError("\(where_) rethrows; write its double by hand", at: declaration.name)
        }
        let thrown = throwsClause?.type
        let thrownName = thrown?.trimmedDescription
        if let thrown, let name = thrown.tokens(viewMode: .sourceAccurate).first(where: { generics[$0.text] != nil }) {
            throw UnderstudyError(
                "\(where_) throws its generic parameter '\(name.text)'; write its double by hand",
                at: thrown
            )
        }
        // `throws(Never)` throws nothing, and `throws(any Error)` is a plain `throws`.
        throwsError = throwsClause != nil && thrownName != "Never"
        if throwsError, let thrownName, !Self.untypedErrors.contains(thrownName) {
            typedError = thrownName
        } else {
            typedError = nil
        }
        isAsync = signature.effectSpecifiers?.asyncSpecifier != nil
        labels = signature.parameterClause.parameters.map(\.firstName.text)
        parameters = try signature.parameterClause.parameters.map { parameter in
            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else {
                throw UnderstudyError(
                    "\(where_) has a parameter with no name; name it",
                    at: parameter,
                    fixIt: .replace(
                        message: UnderstudyFixIt("Add a name"),
                        oldNode: parameter,
                        newNode: named(parameter)
                    )
                )
            }
            let escapes = parameter.type.as(AttributedTypeSyntax.self)?.attributes.contains { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "escaping"
            } ?? false
            return Parameter(
                name: name,
                type: try Self.storedType(of: parameter, generics: generics, in: where_),
                escapes: escapes
            )
        }
        let returnType = signature.returnClause?.type
        self.returnType = returnType
        let unwrapped = returnType?.as(OptionalTypeSyntax.self)?.wrappedType ?? returnType
        if let returnType, let unwrapped, let erased = Self.erased(unwrapped, generics: generics) {
            let optional = returnType.is(OptionalTypeSyntax.self)
            output = optional ? "(\(erased.type))?" : erased.type
            returnedGeneric = unwrapped.trimmedDescription
            returnedParameter = erased.parameter
            returnsNothing = false
            returnsOptional = optional
            returnsFunction = false
        } else if let returnType {
            try Self.refuseNested(returnType, generics: generics, in: where_)
            returnedGeneric = nil
            returnedParameter = nil
            let text = returnType.trimmedDescription
            if returnType.is(SomeOrAnyTypeSyntax.self), text.hasPrefix("some ") {
                throw UnderstudyError("\(where_) returns an opaque type; write its double by hand", at: declaration.name)
            }
            output = text
            returnsNothing = text == "Void" || text == "()"
            returnsOptional = returnType.is(OptionalTypeSyntax.self)
                || returnType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                || text.hasPrefix("Optional<")
            returnsFunction = Self.isFunction(returnType)
        } else {
            returnedGeneric = nil
            returnedParameter = nil
            output = "Swift.Void"
            returnsNothing = true
            returnsOptional = false
            returnsFunction = false
        }
    }

    /// The ways to write a typed `throws` that is a plain `throws`.
    private static let untypedErrors = ["any Error", "Error", "any Swift.Error", "Swift.Error"]

    /// Whether a type is a closure, such as `() -> Void`, `@Sendable () -> Void` or `(() -> Void)`.
    static func isFunction(_ type: TypeSyntax) -> Bool {
        if type.is(FunctionTypeSyntax.self) {
            return true
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunction(attributed.baseType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first, only.firstName == nil {
            return isFunction(only.type)
        }
        return false
    }

}
