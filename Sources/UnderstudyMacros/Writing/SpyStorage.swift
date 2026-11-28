//
//  SpyStorage.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntax

/// An answer the double's initializer takes: the spy it fills, the type it takes, and the obvious
/// value it defaults to, if the type has one.
private typealias InitialAnswer = (name: String, output: String, obvious: String?)

extension GenerateSpiesMacro {
    /// One stored spy per requirement, and an initializer that takes every answer with no safe
    /// default, defaulting those with an obvious value. An actor's spies are `nonisolated`, so a
    /// test reads them without `await`.
    static func storage(
        for requirements: [any Requirement],
        in typeName: String,
        access: String,
        isActor: Bool,
        isGlobalActor: Bool = false,
        parents: [ProtocolSpy.Parent] = []
    ) throws -> [DeclSyntax] {
        let names = try spyNames(for: requirements)
        let prefix = access.isEmpty ? "" : access + " "
        let spyPrefix = prefix + (isActor ? "nonisolated " : "")
        let statics = zip(requirements, names).filter { $0.0.isStatic }
        // `var` because the parents' spies, the instance spies and the initializer are added below.
        var declarations = try staticStorage(for: statics, in: typeName, prefix: prefix, isGlobalActor: isGlobalActor)
        for parent in parents {
            declarations.append("\(raw: spyPrefix)let \(raw: parent.property): \(raw: parent.spyType)")
        }
        let instances = zip(requirements, names).filter { !$0.0.isStatic }
        let (spies, answers) = instanceSpies(for: instances, prefix: spyPrefix)
        declarations += spies
        // A `nonisolated` protocol `init` delegates to the spy's own initializer, which must then
        // be `nonisolated` too, or the call would cross into the global actor.
        let delegatesNonisolated = requirements.contains { ($0 as? InitializerRequirement)?.isNonisolated == true }
        let initializerPrefix = prefix + (delegatesNonisolated ? "nonisolated " : "")
        if let initializer = initializer(taking: parents, and: answers, prefix: initializerPrefix) {
            declarations.append(initializer)
        }
        return declarations
    }

    /// The stored spies of the requirements that aren't static, and the answers the initializer
    /// must take for them. A closure answer is taken `@escaping`, because the spy keeps it. An
    /// answer with an obvious value defaults to it, so the test passes only the answers that
    /// matter to it.
    private static func instanceSpies(
        for requirements: [(any Requirement, String)],
        prefix: String
    ) -> (spies: [DeclSyntax], answers: [InitialAnswer]) {
        // `var` because the loop adds each requirement's spies.
        var spies: [DeclSyntax] = []
        // `var` because the loop adds the answer of each requirement that needs one.
        var answers: [InitialAnswer] = []
        for (requirement, name) in requirements {
            if let setSpyType = requirement.setSpyType {
                spies.append("\(raw: prefix)let \(raw: setSpyName(for: name)) = \(raw: setSpyType)()")
            }
            if requirement.needsAnswer {
                spies.append("\(raw: prefix)let \(raw: name): \(raw: requirement.spyType)")
                answers.append((name, requirement.answerType, requirement.obviousAnswer))
            } else {
                let spy = "\(requirement.spyType)(returning: \(requirement.defaultAnswer))"
                spies.append("\(raw: prefix)let \(raw: name) = \(raw: spy)")
            }
        }
        return (spies, answers)
    }

    /// The initializer, or `nil` when it would take nothing. It takes each parent protocol's spy
    /// first, then names each answer after its requirement: `init(now:)` fills `nowSpy`, and
    /// `init(subscript:)` fills `subscriptSpy`, with the keyword in backticks where it's a name.
    private static func initializer(
        taking parents: [ProtocolSpy.Parent],
        and answers: [InitialAnswer],
        prefix: String
    ) -> DeclSyntax? {
        guard !answers.isEmpty || !parents.isEmpty else {
            return nil
        }
        let parameters =
            parents.map { "\($0.label): \($0.spyType)" }
            + answers.map { answer in
                "\(label(of: answer.name)): \(answer.output)" + (answer.obvious.map { " = \($0)" } ?? "")
            }
        let assignments =
            parents.map { "self.\($0.property) = \($0.label)" }
            + answers.map { answer in
                let name = label(of: answer.name)
                return "self.\(answer.name) = .init(returning: \(name == "subscript" ? "`subscript`" : name))"
            }
        let what =
            parents.isEmpty
            ? "the answer each requirement gives"
            : "the spies of the protocols it inherits, and the answer each requirement gives"
        return """
            /// Creates the double with \(raw: what) until the test scripts another.
            \(raw: prefix)init(\(raw: parameters.joined(separator: ", "))) {
            \(raw: assignments.joined(separator: "\n"))
            }
            """
    }

    /// The box of static spies, held in a task local so each test can have its own, and a static
    /// property per spy that reads the current box. Under a global actor they are `nonisolated`,
    /// so the conformance to `StaticSpies` doesn't cross into the actor's code and a test reads the
    /// spies without `await`.
    private static func staticStorage(
        for statics: [(any Requirement, String)],
        in typeName: String,
        prefix: String,
        isGlobalActor: Bool
    ) throws -> [DeclSyntax] {
        guard !statics.isEmpty else {
            return []
        }
        let box = "__understudy_statics"
        let isolation = isGlobalActor ? "nonisolated " : ""
        let spies = try statics.map { requirement, name in
            "let \(name) = \(requirement.spyType)(returning: \(try firstStaticAnswer(of: requirement)))"
        }
        let readers: [DeclSyntax] = statics.map { requirement, name in
            """
            /// The spy for `\(raw: requirement.baseName)` in this test's box: `.freshSpies(_:)`
            /// gives each test its own.
            \(raw: prefix)\(raw: isolation)static var \(raw: name): \(raw: requirement.spyType) {
            \(raw: box).get().\(raw: name)
            }
            """
        }
        let current = "_Concurrency.TaskLocal(wrappedValue: __UnderstudyStatics())"
        let fresh = "@Sendable (_ test: () async throws -> \(GeneratedName.void)) async throws -> \(GeneratedName.void)"
        return [
            """
            /// The static spies of one test, or of every test that runs without `.freshSpies(_:)`.
            \(raw: prefix)final class __UnderstudyStatics: \(raw: GeneratedName.sendable) {
            \(raw: spies.joined(separator: "\n"))
            }
            """,
            "private \(raw: isolation)static let \(raw: box) = \(raw: current)",
            """
            \(raw: prefix)\(raw: isolation)static let withFreshSpies: \(raw: fresh) = { test in
            try await \(raw: typeName).\(raw: box).withValue(__UnderstudyStatics()) {
            try await test()
            }
            }
            """,
        ] + readers
    }

    /// The answer a static spy starts with. No initializer takes it, so it is the obvious one; a
    /// requirement whose answer has none is refused.
    private static func firstStaticAnswer(of requirement: any Requirement) throws -> String {
        guard let first = requirement.needsAnswer ? requirement.obviousAnswer : requirement.defaultAnswer else {
            throw UnderstudyError(
                "'\(requirement.baseName)' is static, so no initializer takes its first answer, and "
                    + "'\(requirement.answerType)' has no obvious one; make it optional, or write its "
                    + "double by hand",
                at: requirement.nameToken
            )
        }
        return first
    }

    /// The initializer's label for a spy's answer: the spy's name without its suffix.
    static func label(of spy: String) -> String {
        String(spy.dropLast(spySuffix.count))
    }
}
