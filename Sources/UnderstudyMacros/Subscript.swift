//
//  Subscript.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// One subscript a double stands in for, read from its declaration: a subscript of a class whose
/// `get`, and maybe `set`, are marked `@Spied` with empty bodies, or a subscript requirement of a
/// protocol. Its gets go to one spy, and its sets, when it has any, to a second.
struct Subscript: SpiedMember {
    let declaration: SubscriptDeclSyntax
    let parameters: [Requirement.Parameter]
    let output: String
    let returnsOptional: Bool
    let returnsFunction: Bool
    /// Whether it has a setter, which gets a second spy.
    let isSettable: Bool

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
            return parameters.first?.type ?? "Void"
        }
        return "(" + parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ") + ")"
    }

    var spyType: String {
        "Spy<\(input), \(output)>"
    }

    /// A spy that keeps each set as a labelled tuple of the indices and the new value.
    var setSpyType: String? {
        guard isSettable else {
            return nil
        }
        let fields = parameters.map { "\($0.name): \($0.type)" } + ["newValue: \(output)"]
        return "Spy<(\(fields.joined(separator: ", "))), Void>"
    }

    var needsAnswer: Bool {
        !returnsOptional
    }

    var defaultAnswer: String {
        "nil"
    }

    var answerType: String {
        (returnsFunction ? "@escaping " : "") + output
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
        let where_ = "'subscript'"
        let keyword = declaration.subscriptKeyword
        let modifiers = declaration.modifiers.map(\.name.text)
        if modifiers.contains("static") || modifiers.contains("class") {
            throw UnderstudyError("\(where_) is static; write its double by hand", at: keyword)
        }
        if declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
            throw UnderstudyError("\(where_) is generic; write its double by hand", at: keyword)
        }
        let accessors = declaration.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) ?? []
        if accessors.contains(where: { $0.effectSpecifiers != nil }) {
            throw UnderstudyError("\(where_) is async or throws; write its double by hand", at: keyword)
        }
        if !inProtocol, checkingAccessors, accessors.isEmpty || accessors.contains(where: { !Self.isSpied($0) }) {
            throw UnderstudyError(
                "\(where_) has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                    + "or { @Spied get {} } with no set",
                at: keyword
            )
        }
        isSettable = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
        parameters = try declaration.parameterClause.parameters.map { parameter in
            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else {
                throw UnderstudyError("\(where_) has an index with no name; name it", at: parameter)
            }
            return Requirement.Parameter(
                name: name,
                type: try Requirement.storedType(of: parameter, generics: [:], in: where_),
                escapes: false
            )
        }
        let returnType = declaration.returnClause.type
        output = returnType.trimmedDescription
        returnsOptional = returnType.is(OptionalTypeSyntax.self)
            || returnType.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || output.hasPrefix("Optional<")
        returnsFunction = Requirement.isFunction(returnType)
    }
}
