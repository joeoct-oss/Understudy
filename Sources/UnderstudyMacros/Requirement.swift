//
//  Requirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// A requirement a double stands in for, with its own spy: a function or a property.
protocol SpiedMember {
    /// The name the requirement is declared with, where errors about it point.
    var nameToken: TokenSyntax { get }
    /// The argument labels, which tell overloads apart; none for a property.
    var labels: [String] { get }
    /// The spy's type.
    var spyType: String { get }
    /// Whether the double's initializer must ask for the spy's first answer.
    var needsAnswer: Bool { get }
    /// The first answer when the initializer doesn't ask for one: `()` or `nil`.
    var defaultAnswer: String { get }
    /// The type the initializer takes the answer as, `@escaping` for a closure the spy keeps.
    var answerType: String { get }
    /// What the requirement goes through to reach `spy` on a class.
    func forwarder(spy: String) -> DeclSyntax
    /// The requirement written out to call `spy`, for the spy class next to a protocol.
    func implementation(spy: String, access: String) -> DeclSyntax
}

extension SpiedMember {
    /// The name the spy is named after.
    var baseName: String {
        nameToken.text
    }
}

/// One function requirement a double stands in for, read from its declaration.
struct Requirement: SpiedMember {
    /// One parameter: the name the body uses and the type the spy records.
    struct Parameter {
        let name: String
        let type: String
        /// Whether the requirement takes it `@escaping`; the forwarder must too, to pass it on.
        let escapes: Bool
    }

    let declaration: FunctionDeclSyntax
    let labels: [String]
    let parameters: [Parameter]
    let throwsError: Bool
    /// The error type a typed `throws` names, such as `AuthError`, which the body rethrows the
    /// spy's error as; `nil` for a plain `throws`, `throws(any Error)` or no `throws`.
    let typedError: String?
    let isAsync: Bool
    let output: String
    let returnsNothing: Bool
    let returnsOptional: Bool
    /// Whether the answer is a closure, which the double's initializer must take `@escaping`.
    let returnsFunction: Bool
    /// The generic parameter the requirement returns, as `T` or `T?`, whose answer the body casts
    /// back; `nil` when it returns no generic parameter.
    let returnedGeneric: String?

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

    /// The statements that call `spy` and return its answer, cast back to the generic parameter
    /// the requirement returns, with the spy's error rethrown as the typed `throws` names. A
    /// wrong-typed answer or error stops the test, naming the spy and both types.
    func body(on spy: String) -> String {
        guard let typedError else {
            return answer(on: spy)
        }
        let wrongType =
            "fatalError(\"@GenerateSpies: \(spy) threw \\(type(of: error)), not \\(\(typedError).self)\")"
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
            "fatalError(\"@GenerateSpies: \(spy) answered \\(type(of: \(answer))), not \\(\(generic).self)\")"
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
        if modifiers.contains("static") || modifiers.contains("class") {
            throw UnderstudyError("\(where_) is static; write its double by hand", at: declaration.name)
        }
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
                throw UnderstudyError("\(where_) has a parameter with no name; name it", at: parameter)
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
        returnedGeneric = try signature.returnClause.flatMap { clause in
            try Self.returnedGeneric(clause.type, generics: generics, in: where_)
        }
        if let generic = returnedGeneric, let erased = generics[generic] {
            let optional = signature.returnClause?.type.is(OptionalTypeSyntax.self) == true
            output = optional ? "(\(erased))?" : erased
            returnsNothing = false
            returnsOptional = optional
            returnsFunction = false
        } else if let returnType = signature.returnClause?.type {
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
            output = "Void"
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

    /// Each generic parameter's name, and the type its spy records it as: `any` of its constraints,
    /// or `Any` when it has none. Refuses what a spy can't record: a `where` clause or a pack.
    private static func erasedGenerics(of declaration: FunctionDeclSyntax, in where_: String) throws -> [String: String] {
        guard let clause = declaration.genericParameterClause else {
            return [:]
        }
        if declaration.genericWhereClause != nil || clause.genericWhereClause != nil {
            throw UnderstudyError("\(where_) has a where clause; write its double by hand", at: declaration.name)
        }
        var generics: [String: String] = [:]
        for parameter in clause.parameters {
            if parameter.specifier != nil {
                throw UnderstudyError("\(where_) takes a parameter pack; write its double by hand", at: declaration.name)
            }
            generics[parameter.name.text] = parameter.inheritedType.map { "any " + $0.trimmedDescription } ?? "Any"
        }
        return generics
    }

    /// The generic parameter a return type is, `T` or `T?`; `nil` when it mentions none. Refuses a
    /// generic parameter inside another type, such as `[T]`.
    private static func returnedGeneric(
        _ type: TypeSyntax,
        generics: [String: String],
        in where_: String
    ) throws -> String? {
        let whole = type.as(OptionalTypeSyntax.self)?.wrappedType ?? type
        if generics[whole.trimmedDescription] != nil {
            return whole.trimmedDescription
        }
        try refuseNested(type, generics: generics, in: where_)
        return nil
    }

    /// Refuses a type that mentions a generic parameter without being it.
    private static func refuseNested(_ type: some SyntaxProtocol, generics: [String: String], in where_: String) throws {
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
    private static func storedType(
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
            if kept.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "autoclosure" }) {
                throw UnderstudyError("\(where_) takes an autoclosure; write its double by hand", at: parameter)
            }
            type = TypeSyntax(attributed.with(\.attributes, kept))
        }
        var text = type.trimmedDescription
        if let erased = generics[text] {
            text = erased
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

/// One property requirement a double stands in for, read from its declaration: a `@SpiedProperty var` with
/// a type and nothing else on a class, or a `var` requirement of a protocol.
struct Property: SpiedMember {
    let nameToken: TokenSyntax
    let type: String
    let isOptional: Bool
    let isFunction: Bool

    var labels: [String] {
        []
    }

    var spyType: String {
        "PropertySpy<\(type)>"
    }

    var needsAnswer: Bool {
        !isOptional
    }

    var defaultAnswer: String {
        "nil"
    }

    var answerType: String {
        (isFunction ? "@escaping " : "") + type
    }

    /// The private property `@GenerateSpies` writes for this property on a class, which the
    /// accessors `@Spied` writes go through.
    var forwarderName: String {
        "__understudy_property_" + nameToken.text
    }

    /// Reads a property, or explains why it can't be written. On a class it must have no value
    /// and no accessors; a protocol's always has accessors.
    init(_ declaration: VariableDeclSyntax, inProtocol: Bool) throws {
        guard declaration.bindings.count == 1, let binding = declaration.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw UnderstudyError("declare one property at a time", at: declaration.bindings)
        }
        nameToken = pattern.identifier
        let where_ = "'\(pattern.identifier.text)'"
        let modifiers = declaration.modifiers.map(\.name.text)
        if modifiers.contains("static") || modifiers.contains("class") {
            throw UnderstudyError("\(where_) is static; write its double by hand", at: pattern.identifier)
        }
        if declaration.bindingSpecifier.tokenKind == .keyword(.let) {
            throw UnderstudyError("\(where_) is a let; declare it as a var", at: pattern.identifier)
        }
        guard let annotation = binding.typeAnnotation else {
            throw UnderstudyError("\(where_) has no type; write its type", at: pattern.identifier)
        }
        if binding.initializer != nil {
            throw UnderstudyError(
                "\(where_) has a value; give it none, the double's initializer takes it",
                at: pattern.identifier
            )
        }
        if !inProtocol, binding.accessorBlock != nil {
            throw UnderstudyError("\(where_) is @SpiedProperty, so give it no accessors", at: pattern.identifier)
        }
        let type = annotation.type
        self.type = type.trimmedDescription
        isOptional = type.is(OptionalTypeSyntax.self)
            || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || self.type.hasPrefix("Optional<")
        isFunction = Requirement.isFunction(type)
    }
}

/// Names each requirement's spy: its base name, with its argument labels added when another
/// requirement shares the base name.
func spyNames(for requirements: [any SpiedMember]) throws -> [String] {
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
            at: requirement.nameToken
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
        self.description = "@GenerateSpies: " + description
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
