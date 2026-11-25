//
//  Requirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// One function requirement a double stands in for, read from its declaration.
struct Requirement {
    /// One parameter: the name the body uses and the type the spy records.
    struct Parameter {
        let name: String
        let type: String
        /// Whether the requirement takes it `@escaping`; the forwarder must too, to pass it on.
        let escapes: Bool
    }

    let declaration: FunctionDeclSyntax
    let baseName: String
    let labels: [String]
    let parameters: [Parameter]
    let throwsError: Bool
    let output: String
    let returnsNothing: Bool
    let returnsOptional: Bool
    /// Whether the answer is a closure, which the double's initializer must take `@escaping`.
    let returnsFunction: Bool

    /// The spy's input type: nothing, the one parameter's type, or a labelled tuple of them all.
    var input: String {
        switch parameters.count {
        case 0:
            return "Void"
        case 1:
            return parameters[0].type
        default:
            return "(" + parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }

    /// The spy's type.
    var spyType: String {
        let kind = throwsError ? "ThrowingSpy" : "Spy"
        return "\(kind)<\(input), \(output)>"
    }

    /// Whether the double's initializer must ask for this requirement's answer.
    var needsAnswer: Bool {
        !returnsNothing && !returnsOptional
    }

    /// The name of the private function `@Understudy` writes for this requirement on a class. The
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
        baseName = declaration.name.text
        let where_ = "'\(declaration.name.text)'"
        if declaration.genericParameterClause != nil {
            throw UnderstudyError("\(where_) is generic; write its double by hand", at: declaration)
        }
        let modifiers = declaration.modifiers.map(\.name.text)
        if modifiers.contains("static") || modifiers.contains("class") {
            throw UnderstudyError("\(where_) is static; write its double by hand", at: declaration)
        }
        if modifiers.contains("mutating") {
            throw UnderstudyError("\(where_) is mutating; @Understudy writes classes", at: declaration)
        }
        let signature = declaration.signature
        let throwsClause = signature.effectSpecifiers?.throwsClause
        if throwsClause?.type != nil {
            throw UnderstudyError("\(where_) uses typed throws; write its double by hand", at: declaration)
        }
        if throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows) {
            throw UnderstudyError("\(where_) rethrows; write its double by hand", at: declaration)
        }
        throwsError = throwsClause != nil
        labels = signature.parameterClause.parameters.map(\.firstName.text)
        parameters = try signature.parameterClause.parameters.map { parameter in
            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else {
                throw UnderstudyError("\(where_) has a parameter with no name; name it", at: parameter)
            }
            let escapes = parameter.type.as(AttributedTypeSyntax.self)?.attributes.contains { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "escaping"
            } ?? false
            return Parameter(
                name: name,
                type: try Self.storedType(of: parameter, in: where_),
                escapes: escapes
            )
        }
        if let returnType = signature.returnClause?.type {
            let text = returnType.trimmedDescription
            if returnType.is(SomeOrAnyTypeSyntax.self), text.hasPrefix("some ") {
                throw UnderstudyError("\(where_) returns an opaque type; write its double by hand", at: declaration)
            }
            output = text
            returnsNothing = text == "Void" || text == "()"
            returnsOptional = returnType.is(OptionalTypeSyntax.self)
                || returnType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                || text.hasPrefix("Optional<")
            returnsFunction = Self.isFunction(returnType)
        } else {
            output = "Void"
            returnsNothing = true
            returnsOptional = false
            returnsFunction = false
        }
    }

    /// Whether a type is a closure, such as `() -> Void`, `@Sendable () -> Void` or `(() -> Void)`.
    private static func isFunction(_ type: TypeSyntax) -> Bool {
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

    /// The type a spy records for a parameter: `@escaping` dropped, `some` turned into `any`, and a
    /// variadic parameter as an array.
    private static func storedType(of parameter: FunctionParameterSyntax, in where_: String) throws -> String {
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
            if kept.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "autoclosure" }) {
                throw UnderstudyError("\(where_) takes an autoclosure; write its double by hand", at: parameter)
            }
            type = TypeSyntax(attributed.with(\.attributes, kept))
        }
        var text = type.trimmedDescription
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self), someOrAny.someOrAnySpecifier.text == "some" {
            text = "any " + someOrAny.constraint.trimmedDescription
        }
        if parameter.ellipsis != nil {
            text = "[\(text)]"
        }
        return text
    }
}

/// Names each requirement's spy: its base name, with its argument labels added when another
/// requirement shares the base name.
func spyNames(for requirements: [Requirement]) throws -> [String] {
    let counts = Dictionary(grouping: requirements, by: \.baseName).mapValues(\.count)
    let names = requirements.map { requirement in
        guard counts[requirement.baseName, default: 0] > 1 else {
            return requirement.baseName + spySuffix
        }
        let labels = requirement.labels.filter { $0 != "_" }
        return requirement.baseName + labels.map(capitalized).joined() + spySuffix
    }
    var seen = Set<String>()
    for (requirement, name) in zip(requirements, names) where !seen.insert(name).inserted {
        throw UnderstudyError(
            "two requirements would both be spied on as '\(name)'; rename one",
            at: requirement.declaration
        )
    }
    return names
}

/// Every spy's name ends with this, so a spy never shares its name with the function it stands in
/// for: `refreshSpy` for `refresh()`, `productSpy` for `product(id:)`.
let spySuffix = "Spy"

/// `label` with its first letter in upper case.
private func capitalized(_ label: String) -> String {
    label.prefix(1).uppercased() + label.dropFirst()
}

/// A requirement the macro can't write, explained to the person writing the double, at the code
/// it is about when there is one.
struct UnderstudyError: Error, CustomStringConvertible, DiagnosticMessage {
    let description: String
    /// The code the error is about, such as the requirement or its parameter.
    let node: Syntax?

    init(_ description: String, at node: (some SyntaxProtocol)? = Optional<Syntax>.none) {
        self.description = "@Understudy: " + description
        self.node = node.map { Syntax($0) }
    }

    var message: String {
        description
    }

    var diagnosticID: MessageID {
        MessageID(domain: "Understudy", id: "error")
    }

    var severity: DiagnosticSeverity {
        .error
    }
}
