//
//  InitializerRequirement.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// An `init` a protocol declares. Its spy is static, since the code under test calls it before
/// any double exists, and keeps the arguments each call was given; the spy class's initializer
/// with the protocol's signature builds the double with its first answers, then calls the spy.
struct InitializerRequirement: Requirement {
    /// How the spy class's initializer with the protocol's signature builds the double.
    enum Delegation {
        /// It is the double's one initializer, since the double's own would take nothing.
        case designated
        /// It calls the double's own initializer with `call`, passing every answer, so a call
        /// can never pick itself; `keyword` is `convenience ` in a class, empty in an actor.
        case delegating(call: String, keyword: String)
    }

    /// The requirement as written.
    let declaration: InitializerDeclSyntax
    /// The argument labels, `_` for none.
    let labels: [String]
    /// Its parameters, as the spy records them.
    let parameters: [FunctionRequirement.Parameter]
    /// Whether it throws, so its spy is a `ThrowingSpy` and a test can make it throw.
    let throwsError: Bool
    /// The error type a typed `throws` names, which the body rethrows the spy's error as.
    let typedError: String?
    /// Whether it is async, so the body goes through `respond(to:)`.
    let isAsync: Bool
    /// How it builds the double; the protocol's spy sets it once it knows the double's own
    /// initializer.
    var delegation = Delegation.designated

    /// How errors name it, such as `'init(user:)'`.
    var subject: String {
        Self.subject(labels: labels)
    }

    /// The `init` keyword, which errors point at and the spy is named after.
    var nameToken: TokenSyntax {
        declaration.initKeyword
    }

    /// `Spy<Input, Void>`, or `ThrowingSpy<Input, Void>` for an `init` that throws.
    var spyType: String {
        let kind = throwsError ? GeneratedName.throwingSpy : GeneratedName.spy
        return "\(kind)<\(parameters.recordedType), \(GeneratedName.void)>"
    }

    /// It answers nothing, so the double's initializer never asks for an answer.
    let needsAnswer = false
    /// Its spy starts answering `()`.
    let defaultAnswer = "()"
    /// It answers `Void`.
    let answerType = GeneratedName.void
    /// `()`, the one answer of `Void`.
    let obviousAnswer: String? = "()"
    /// Static: the code under test calls it before any double exists.
    let isStatic = true

    /// Reads an `init`, or explains why it can't be written: failable, generic, `rethrows`, or
    /// with a parameter that has no name.
    init(_ declaration: InitializerDeclSyntax) throws {
        self.declaration = declaration
        let parameterList = declaration.signature.parameterClause.parameters
        labels = parameterList.map(\.firstName.text)
        let subject = Self.subject(labels: labels)
        // A generic `init` is refused below, so there are no generic parameters to erase.
        let noGenerics: [String: String] = [:]
        if declaration.optionalMark != nil {
            throw UnderstudyError(
                "\(subject) is failable, and its spy has no answer that means fail; write its double by hand",
                at: declaration.initKeyword
            )
        }
        if declaration.genericParameterClause != nil || declaration.genericWhereClause != nil {
            throw UnderstudyError("\(subject) is generic; write its double by hand", at: declaration.initKeyword)
        }
        let effects = try FunctionRequirement.Effects(
            of: declaration.signature,
            named: declaration.initKeyword,
            generics: noGenerics,
            in: subject
        )
        throwsError = effects.throwsError
        typedError = effects.typedError
        isAsync = effects.isAsync
        parameters = try parameterList.map { parameter in
            try FunctionRequirement.parameter(parameter, generics: noGenerics, in: subject)
        }
    }

    /// How errors name an `init` with these labels, such as `'init(user:)'`.
    static func subject(labels: [String]) -> String {
        "'init(" + labels.map { $0 + ":" }.joined() + ")'"
    }

    /// The initializer with the protocol's signature, for the spy class written next to it.
    func implementation(spy: String, access: String) -> DeclSyntax {
        let prefix = access.isEmpty ? "" : access + " "
        let signature = declaration.signature.trimmedDescription
        guard case .delegating(let call, let keyword) = delegation else {
            return """
                /// The protocol's `init`: records the call on `\(raw: spy)`.
                \(raw: prefix)init\(raw: signature) {
                \(raw: body(on: spy))
                }
                """
        }
        return """
            /// The protocol's `init`: builds the double with its first answers, then records the call
            /// on `\(raw: spy)`.
            \(raw: prefix)\(raw: keyword)init\(raw: signature) {
            \(raw: call)
            \(raw: body(on: spy))
            }
            """
    }

    /// The statement that records the call on the static spy, through `respond(to:)` when the
    /// `init` is async, with the spy's error rethrown as the typed `throws` names.
    private func body(on spy: String) -> String {
        let attempt = throwsError ? "try " : ""
        let argument = parameters.recordedArgument
        let call =
            isAsync
            ? "\(attempt)await Self.\(spy).respond(to: \(parameters.isEmpty ? "()" : argument))"
            : "\(attempt)Self.\(spy)(\(argument))"
        guard let typedError else {
            return call
        }
        let wrongType =
            "\(GeneratedName.fatalError)(\"@GenerateSpies: \(spy) threw "
            + "\\(Swift.type(of: error)), not \\(\(typedError).self)\")"
        return """
            do {
            \(call)
            } catch let error as \(typedError) {
            throw error
            } catch {
            \(wrongType)
            }
            """
    }
}
