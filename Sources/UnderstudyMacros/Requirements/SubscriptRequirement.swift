//
//  SubscriptRequirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// One subscript a double stands in for, read from its declaration: a subscript of a class whose
/// `get`, and maybe `set`, are marked `@Spied` with empty bodies, or a subscript requirement of a
/// protocol. Its gets go to one spy, and its sets, when it has any, to a second.
///
/// - `Requirement`: the macros write its spies and accessors like any other requirement's.
struct SubscriptRequirement: SpiedMember {
    /// The subscript as written.
    let declaration: SubscriptDeclSyntax
    /// Its indices, as the spy records them.
    let parameters: [FunctionRequirement.Parameter]
    /// The type the get spy answers with.
    let output: String
    /// Whether it returns an optional, so the spy can start with `nil`.
    let returnsOptional: Bool
    /// Whether it returns a closure, which the initializer takes `@escaping`.
    let returnsFunction: Bool
    /// Whether it has a setter, which gets a second spy.
    let isSettable: Bool

    /// The `subscript` keyword, where errors point.
    var nameToken: TokenSyntax {
        declaration.subscriptKeyword
    }

    /// The indices' names, which tell overloads apart.
    var labels: [String] {
        parameters.map(\.name)
    }

    /// The get spy's input: the one index's type, or a labelled tuple of them all.
    var input: String {
        guard parameters.count > 1 else {
            return parameters.first?.type ?? GeneratedName.void
        }
        return "(" + parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ") + ")"
    }

    /// The get spy's type.
    var spyType: String {
        "\(GeneratedName.spy)<\(input), \(output)>"
    }

    /// A spy that keeps each set as a labelled tuple of the indices and the new value.
    var setSpyType: String? {
        guard isSettable else {
            return nil
        }
        let fields = parameters.map { "\($0.name): \($0.type)" } + ["newValue: \(output)"]
        return "\(GeneratedName.spy)<(\(fields.joined(separator: ", "))), \(GeneratedName.void)>"
    }

    /// An answer is needed unless it returns an optional.
    var needsAnswer: Bool {
        !returnsOptional
    }

    /// `nil`, since only an optional subscript has no answer to ask for.
    var defaultAnswer: String {
        "nil"
    }

    /// The output, `@escaping` when it is a closure.
    var answerType: String {
        (returnsFunction ? "@escaping " : "") + output
    }

    /// The obvious value of the return type, when it has one.
    var obviousAnswer: String? {
        obviousDefault(of: declaration.returnClause.type)
    }

    /// The label of the private subscript `@GenerateSpies` writes on a class, which the `@Spied`
    /// accessors go through, so an overload reaches its own spies.
    static let forwarderLabel = "__understudy"

    /// The argument the get spy records.
    private var getArgument: String {
        guard parameters.count > 1 else {
            return parameters[0].name
        }
        return "(" + parameters.map { "\($0.name): \($0.name)" }.joined(separator: ", ") + ")"
    }

    /// The argument the set spy records.
    private var setArgument: String {
        "(" + (parameters.map { "\($0.name): \($0.name)" } + ["newValue: newValue"]).joined(separator: ", ") + ")"
    }

    /// Whether an accessor is marked `@Spied` and has an empty body, which `@Spied` writes.
    private static func isSpied(_ accessor: AccessorDeclSyntax) -> Bool {
        let marked = accessor.attributes.contains { element in
            let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
            return name == "Spied" || name == "Understudy.Spied"
        }
        return marked && accessor.body?.statements.isEmpty == true
    }

    /// The getter and setter that call the spies.
    func accessors(spy: String) -> String {
        let get = "get {\nself.\(spy)(\(getArgument))\n}"
        guard isSettable else {
            return get
        }
        return get + "\nset {\nself.\(setSpyName(for: spy))(\(setArgument))\n}"
    }

    /// The private subscript a subscript's `@Spied` accessors go through on a class: it takes the
    /// indices after a first label of its own, and calls the spies.
    func forwarder(spy: String) -> DeclSyntax {
        let indices = parameters.enumerated().map { index, parameter in
            let label = index == 0 ? Self.forwarderLabel : parameter.name
            let escaping = parameter.escapes ? "@escaping " : ""
            return "\(label) \(parameter.name): \(escaping)\(parameter.type)"
        }.joined(separator: ", ")
        return """
            private subscript(\(raw: indices)) -> \(raw: output) {
            \(raw: accessors(spy: spy))
            }
            """
    }

    /// The subscript with accessors that call the spies, for the spy class next to a protocol.
    func implementation(spy: String, access: String) -> DeclSyntax {
        // `var` because its trivia and access are set below.
        var written = declaration.with(\.accessorBlock, nil)
        written.leadingTrivia = []
        if !access.isEmpty {
            written.modifiers.append(DeclModifierSyntax(name: .identifier(access), trailingTrivia: .space))
        }
        return """
            \(raw: written.trimmedDescription) {
            \(raw: accessors(spy: spy))
            }
            """
    }

    /// The private subscript `@GenerateSpies` wrote, called with this subscript's indices.
    var forwarderTarget: String {
        let arguments = parameters.enumerated().map { index, parameter in
            "\(index == 0 ? Self.forwarderLabel : parameter.name): \(parameter.name)"
        }.joined(separator: ", ")
        return "self[\(arguments)]"
    }

    /// Reads a subscript, or explains why it can't be written. It has a `get`, and maybe a `set`,
    /// with no effects; on a class, both marked `@Spied`, with empty bodies, unless
    /// `checkingAccessors` is false.
    init(_ declaration: SubscriptDeclSyntax, inProtocol: Bool = false, checkingAccessors: Bool = true) throws {
        self.declaration = declaration
        let subject = "'subscript'"
        let accessors = try Self.writableAccessors(
            of: declaration,
            inProtocol: inProtocol,
            checkingAccessors: checkingAccessors,
            in: subject
        )
        isSettable = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
        parameters = try declaration.parameterClause.parameters.map { parameter in
            try Self.index(parameter, in: subject)
        }
        let returnType = declaration.returnClause.type
        output = returnType.trimmedDescription
        returnsOptional = FunctionRequirement.isOptional(returnType)
        returnsFunction = FunctionRequirement.isFunction(returnType)
    }

    /// The subscript's accessors. Refuses what a spy can't stand in for: a static or generic
    /// subscript, async or throwing accessors, and, on a class, accessors without `@Spied`.
    private static func writableAccessors(
        of declaration: SubscriptDeclSyntax,
        inProtocol: Bool,
        checkingAccessors: Bool,
        in subject: String
    ) throws -> AccessorDeclListSyntax {
        let keyword = declaration.subscriptKeyword
        let modifiers = declaration.modifiers.map(\.name.text)
        if modifiers.contains("static") || modifiers.contains("class") {
            throw UnderstudyError("\(subject) is static; write its double by hand", at: keyword)
        }
        if declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
            throw UnderstudyError("\(subject) is generic; write its double by hand", at: keyword)
        }
        let accessors = declaration.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) ?? []
        if accessors.contains(where: { $0.effectSpecifiers != nil }) {
            throw UnderstudyError("\(subject) is async or throws; write its double by hand", at: keyword)
        }
        if !inProtocol, checkingAccessors, accessors.isEmpty || accessors.contains(where: { !isSpied($0) }) {
            throw UnderstudyError(
                "\(subject) has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                    + "or { @Spied get {} } with no set",
                at: keyword
            )
        }
        return accessors
    }

    /// One index as the spy records it. Refuses an index with no name.
    private static func index(
        _ parameter: FunctionParameterSyntax,
        in subject: String
    ) throws -> FunctionRequirement.Parameter {
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else {
            throw UnderstudyError("\(subject) has an index with no name; name it", at: parameter)
        }
        // A subscript can't be generic, so no index is a generic parameter.
        let noGenerics: [String: String] = [:]
        return FunctionRequirement.Parameter(
            name: name,
            type: try FunctionRequirement.storedType(of: parameter, generics: noGenerics, in: subject),
            escapes: false
        )
    }
}
