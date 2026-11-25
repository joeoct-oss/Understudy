//
//  Requirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftDiagnostics
import SwiftSyntax

/// A requirement a double stands in for, with its own spy: a function, a property or a subscript.
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
    /// The answer the initializer gives when the test passes none, for a type with an obvious one,
    /// such as `""` for `String`; `nil` when the test must pass one.
    var obviousAnswer: String? { get }
    /// The type of a second spy that keeps the sets, for a settable subscript; `nil` for others.
    var setSpyType: String? { get }
    /// Whether it is `static`, so its spy lives in the double's box of static spies.
    var isStatic: Bool { get }
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

    var setSpyType: String? {
        nil
    }

    var isStatic: Bool {
        false
    }
}

/// The obvious value of a type, which the double's initializer gives an answer of that type when
/// the test passes none: `""`, `0`, `false` or an empty collection. `nil` for any other type,
/// including one spelled another way, such as `Swift.String` or a typealias, which the macro
/// can't place.
func obviousDefault(of type: TypeSyntax) -> String? {
    if type.is(ArrayTypeSyntax.self) {
        return "[]"
    }
    if type.is(DictionaryTypeSyntax.self) {
        return "[:]"
    }
    guard let named = type.as(IdentifierTypeSyntax.self) else {
        return nil
    }
    switch named.name.text {
    case "Array", "Set":
        return named.genericArgumentClause == nil ? nil : "[]"
    case "Dictionary":
        return named.genericArgumentClause == nil ? nil : "[:]"
    default:
        return obviousDefaults[named.name.text]
    }
}

/// The obvious value of each type that has one and no generic arguments.
private let obviousDefaults: [String: String] = {
    var defaults = ["String": #""""#, "Bool": "false"]
    let numbers = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "CGFloat", "Decimal",
    ]
    for number in numbers {
        defaults[number] = "0"
    }
    return defaults
}()

/// The name of the spy that keeps a subscript's sets, from the name of the one that keeps its
/// gets: `subscriptSetSpy` for `subscriptSpy`.
func setSpyName(for spy: String) -> String {
    spy.dropLast(spySuffix.count) + "Set" + spySuffix
}

/// One function requirement a double stands in for, read from its declaration.
struct Requirement: SpiedMember {
    /// A type with a generic parameter in it, as its spy records it.
    struct Erased {
        /// The type the spy records, such as `[any Tag]` for `[T]`.
        let type: String
        /// The generic parameter's name, such as `T`.
        let parameter: String
    }

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
            return Erased(type: "Set<AnyHashable>", parameter: element.parameter)
        }
        return nil
    }

    /// Whether a type mentions a generic parameter anywhere in it.
    private static func mentionsGeneric(_ type: some SyntaxProtocol, _ generics: [String: String]) -> Bool {
        type.tokens(viewMode: .sourceAccurate).contains { generics[$0.text] != nil }
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
            if kept.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "autoclosure" }) {
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

/// One property requirement a double stands in for, read from its declaration: a `@SpiedProperty var` with
/// a type and nothing else on a class, or a `var` requirement of a protocol.
struct Property: SpiedMember {
    let nameToken: TokenSyntax
    let isStatic: Bool
    let type: String
    /// The type as written, which ``obviousAnswer`` reads.
    let typeSyntax: TypeSyntax
    let isOptional: Bool
    let isFunction: Bool
    /// The first value written at the declaration, such as `"ana"`, which the spy starts with.
    let initialValue: String?

    var labels: [String] {
        []
    }

    var spyType: String {
        "PropertySpy<\(type)>"
    }

    var needsAnswer: Bool {
        !isOptional && initialValue == nil
    }

    var defaultAnswer: String {
        initialValue ?? "nil"
    }

    var answerType: String {
        (isFunction ? "@escaping " : "") + type
    }

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
        if declaration.bindingSpecifier.tokenKind == .keyword(.let) {
            throw UnderstudyError(
                "\(where_) is a let; declare it as a var",
                at: pattern.identifier,
                fixIt: .replace(
                    message: UnderstudyFixIt("Replace 'let' with 'var'"),
                    oldNode: declaration.bindingSpecifier,
                    newNode: TokenSyntax.keyword(.var, trailingTrivia: .space)
                )
            )
        }
        guard let annotation = binding.typeAnnotation else {
            // The type takes the space the name had before an initializer: `token = 0` becomes
            // `token: <#Type#> = 0`.
            let placeholder = TypeSyntax("<#Type#>").with(\.leadingTrivia, .space)
                .with(\.trailingTrivia, binding.pattern.trailingTrivia)
            let typed = binding.with(\.pattern, binding.pattern.trimmed)
                .with(\.typeAnnotation, TypeAnnotationSyntax(type: placeholder))
            throw UnderstudyError(
                "\(where_) has no type; write its type",
                at: pattern.identifier,
                fixIt: .replace(message: UnderstudyFixIt("Add a type"), oldNode: binding, newNode: typed)
            )
        }
        initialValue = binding.initializer?.value.trimmedDescription
        if !inProtocol, binding.accessorBlock != nil {
            throw UnderstudyError("\(where_) is @SpiedProperty, so give it no accessors", at: pattern.identifier)
        }
        let type = annotation.type
        typeSyntax = type
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
    /// The one change that fixes it, when there is one, which the editor offers as a fix-it.
    let fixIt: FixIt?

    init(_ description: String, at node: (some SyntaxProtocol)? = Optional<Syntax>.none, fixIt: FixIt? = nil) {
        self.description = "@GenerateSpies: " + description
        self.node = node.map { Syntax($0) }
        self.fixIt = fixIt
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

/// `parameter` with a placeholder name after its `_`, which the editor offers to fill in.
func named(_ parameter: FunctionParameterSyntax) -> FunctionParameterSyntax {
    parameter.with(\.firstName, parameter.firstName.with(\.trailingTrivia, .space))
        .with(\.secondName, .identifier("<#name#>"))
}

/// What a fix-it does, as the editor shows it, such as "Replace 'let' with 'var'".
struct UnderstudyFixIt: FixItMessage {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var fixItID: MessageID {
        MessageID(domain: "Understudy", id: "fix-it")
    }
}
