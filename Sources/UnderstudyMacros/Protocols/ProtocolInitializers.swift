//
//  ProtocolInitializers.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

extension ProtocolSpy {
    /// An answer the spy's own initializer takes: its label, its type and the obvious value an
    /// `init` passes for it.
    private struct FirstAnswer {
        let label: String
        let type: String
        let value: String
    }

    /// The requirements, with each `init` set to build the double the way the spy's own
    /// initializer allows. Refuses an `init` the spy can't write: next to an associated type, in
    /// a protocol that inherits another with a spy, next to a requirement whose first answer the
    /// `init` can't take, `nonisolated` under a global actor next to a first answer, or with the
    /// same signature as the spy's own initializer.
    static func settingInitializers(
        of requirements: [any Requirement],
        named spyNames: [String],
        in declaration: ProtocolDeclSyntax,
        isActor: Bool,
        parents: [Parent]
    ) throws -> [any Requirement] {
        let initializers = requirements.compactMap { requirement in requirement as? InitializerRequirement }
        guard let first = initializers.first else {
            return requirements
        }
        let name = declaration.name.text
        let classForm = "use @GenerateSpies on a class or an actor that conforms to '\(name)' instead"
        if declaration.memberBlock.members.contains(where: { member in member.decl.is(AssociatedTypeDeclSyntax.self) })
        {
            throw UnderstudyError(
                "\(first.subject) is next to an associated type, and a spy with associated types is generic, "
                    + "so it can't keep the init's static spy; \(classForm)",
                at: first.nameToken
            )
        }
        if let parent = parents.first {
            throw UnderstudyError(
                "\(first.subject) is in a protocol that inherits '\(parent.type)', whose spy the spy's own "
                    + "initializer takes and the init can't pass; \(classForm)",
                at: first.nameToken
            )
        }
        let answers = try firstAnswers(of: requirements, named: spyNames, in: name)
        let nonisolatedInit = initializers.first { initializer in initializer.nonisolatedModifier != nil }
        if declaration.attributes.hasGlobalActor, !answers.isEmpty, let nonisolated = nonisolatedInit {
            throw UnderstudyError(
                "\(nonisolated.subject) is nonisolated, and the spy's own initializer it calls keeps its first "
                    + "answers on the global actor, which it can't set from outside the actor for an answer that "
                    + "isn't Sendable; \(classForm)",
                at: nonisolated.nameToken
            )
        }
        let delegation = try delegation(for: initializers, answers: answers, isActor: isActor, classForm: classForm)
        return try requirements.map { requirement in
            guard let initializer = requirement as? InitializerRequirement else {
                return requirement
            }
            return try InitializerRequirement(initializer.declaration, delegation: delegation)
        }
    }

    /// The label, type and obvious value of each answer the spy's own initializer takes, in order.
    /// Refuses a requirement whose answer has no obvious value, since the protocol's `init` can't
    /// take it.
    private static func firstAnswers(
        of requirements: [any Requirement],
        named spyNames: [String],
        in name: String
    ) throws -> [FirstAnswer] {
        try zip(requirements, spyNames).filter { requirement, _ in !requirement.isStatic && requirement.needsAnswer }
            .map { requirement, spy in
                guard let value = requirement.obviousAnswer else {
                    throw UnderstudyError(
                        "'\(requirement.baseName)' has no obvious first answer, and '\(name)' declares an init, "
                            + "which can't take one; make it optional, or write its double by hand",
                        at: requirement.nameToken
                    )
                }
                return FirstAnswer(label: GenerateSpiesMacro.label(of: spy), type: requirement.answerType, value: value)
            }
    }

    /// How every `init` builds the double. With no answers to take, the double's own initializer
    /// is `init()`: the protocol's `init()` takes its place and each `init` is designated, or,
    /// without one, each delegates to it. Otherwise each delegates to the double's own
    /// initializer, passing every answer, so a call can never pick itself.
    private static func delegation(
        for initializers: [InitializerRequirement],
        answers: [FirstAnswer],
        isActor: Bool,
        classForm: String
    ) throws -> InitializerRequirement.Delegation {
        let keyword = isActor ? "" : "convenience "
        guard !answers.isEmpty else {
            let replacesOwn = initializers.contains { initializer in initializer.parameters.isEmpty }
            return replacesOwn ? .designated : .delegating(call: "self.init()", keyword: keyword)
        }
        let own = answers.map { answer in (answer.label, spelled(answer.type)) }
        for initializer in initializers {
            // A variadic parameter keeps its `...`: it takes single values, not the answer's array.
            let declared = initializer.declaration.signature.parameterClause.parameters
            let taken = zip(initializer.labels, zip(initializer.parameters, declared)).map { label, parameter in
                (label, spelled(parameter.0.type) + (parameter.1.ellipsis == nil ? "" : "..."))
            }
            guard !taken.isEmpty, isPart(taken, of: own) else {
                continue
            }
            let ownName = InitializerRequirement.subject(labels: answers.map(\.label))
            throw UnderstudyError(
                "\(initializer.subject) takes labels and types the spy's own initializer, \(ownName), takes "
                    + "with defaults, so a test's call to that initializer would reach the init; \(classForm)",
                at: initializer.nameToken
            )
        }
        // Each value names its type, so a literal such as `0` for a `Double` answer can't pick a
        // protocol `init` that takes an `Int` instead.
        let arguments = answers.map { answer in "\(answer.label): \(answer.value) as \(withoutEscaping(answer.type))" }
            .joined(separator: ", ")
        return .delegating(call: "self.init(\(arguments))", keyword: keyword)
    }

    /// `type` without `@escaping`, which an answer is taken with and a value isn't.
    private static func withoutEscaping(_ type: String) -> String {
        let escaping = "@escaping "
        return type.hasPrefix(escaping) ? String(type.dropFirst(escaping.count)) : type
    }

    /// `type` as Swift reads it for an overload, for comparing two signatures: without
    /// `@escaping`, and without the `Swift.` module name, which `Int` and `Swift.Int` differ by.
    private static func spelled(_ type: String) -> String {
        let module = "Swift."
        let plain = withoutEscaping(type)
        return plain.hasPrefix(module) ? String(plain.dropFirst(module.count)) : plain
    }

    /// Whether every parameter of `taken` is among `own`, in the same order: then a call with
    /// `taken`'s labels could reach either initializer, since every answer `own` takes has a
    /// default, and Swift picks the one that leaves no default unused.
    private static func isPart(_ taken: [(String, String)], of own: [(String, String)]) -> Bool {
        // `var` because each parameter found consumes `own` up to it.
        var remaining = own[...]
        for parameter in taken {
            guard let index = remaining.firstIndex(where: { candidate in candidate == parameter }) else {
                return false
            }
            remaining = remaining[(index + 1)...]
        }
        return true
    }
}
