//
//  RefusedInitializers.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// The `init` requirements the macros refuse, each at the `init` or at the requirement that keeps
/// the spy from writing it.
extension ExpansionTests {
    /// Each refused `init`, with the message the macros give and the line and column it points to.
    static let refusedInitializers: [Refused] = [
        refusedInit(
            "a failable init",
            "init?(user: String)",
            "'init(user:)' is failable, and its spy has no answer that means fail; write its double by hand"
        ),
        refusedInit(
            "an implicitly unwrapped failable init",
            "init!(user: String)",
            "'init(user:)' is failable, and its spy has no answer that means fail; write its double by hand"
        ),
        refusedInit("a generic init", "init<User>(user: User)", "'init(user:)' is generic; write its double by hand"),
        refusedInit(
            "an init with a where clause",
            "init(user: String) where Self: Equatable",
            "'init(user:)' is generic; write its double by hand"
        ),
        refusedInit(
            "an init that rethrows",
            "init(make: () throws -> String) rethrows",
            "'init(make:)' rethrows; write its double by hand"
        ),
        Refused(
            name: "an init next to an associated type",
            source: "@GenerateSpies\nprotocol Session {\n    associatedtype User\n    init(user: User)\n}",
            message: "'init(user:)' is next to an associated type, and a spy with associated types is generic, so "
                + "it can't keep the init's static spy; use @GenerateSpies on a class or an actor that conforms "
                + "to 'Session' instead",
            line: 4,
            column: 5
        ),
        Refused(
            name: "an init in a protocol that inherits one with a spy",
            source: "@GenerateSpies\nprotocol Session: Base {\n    init(user: String)\n}",
            message: "'init(user:)' is in a protocol that inherits 'Base', whose spy the spy's own initializer "
                + "takes and the init can't pass; use @GenerateSpies on a class or an actor that conforms to "
                + "'Session' instead",
            line: 3,
            column: 5
        ),
        Refused(
            name: "an init next to a requirement with no obvious first answer",
            source: "@GenerateSpies\nprotocol Session {\n    init(user: String)\n    func account() -> Account\n}",
            message: "'account' has no obvious first answer, and 'Session' declares an init, which can't take "
                + "one; make it optional, or write its double by hand",
            line: 4,
            column: 10
        ),
        Refused(
            name: "an init with the signature of the spy's own initializer",
            source: "@GenerateSpies\nprotocol Session {\n    init(count: Int)\n    func count() -> Int\n}",
            message: "'init(count:)' takes labels and types the spy's own initializer, 'init(count:)', takes "
                + "with defaults, so a test's call to that initializer would reach the init; use @GenerateSpies "
                + "on a class or an actor that conforms to 'Session' instead",
            line: 3,
            column: 5
        ),
        Refused(
            name: "an init that takes some of the spy's own initializer's answers, in order",
            source: "@GenerateSpies\nprotocol Session {\n    init(name: String)\n    var name: String { get }\n"
                + "    func age() -> Int\n}",
            message: "'init(name:)' takes labels and types the spy's own initializer, 'init(name:age:)', takes "
                + "with defaults, so a test's call to that initializer would reach the init; use @GenerateSpies "
                + "on a class or an actor that conforms to 'Session' instead",
            line: 3,
            column: 5
        ),
        Refused(
            name: "an init with the own initializer's type written with its module",
            source: "@GenerateSpies\nprotocol Session {\n    init(count: Swift.Int)\n    func count() -> Int\n}",
            message: "'init(count:)' takes labels and types the spy's own initializer, 'init(count:)', takes "
                + "with defaults, so a test's call to that initializer would reach the init; use @GenerateSpies "
                + "on a class or an actor that conforms to 'Session' instead",
            line: 3,
            column: 5
        ),
        Refused(
            name: "a nonisolated init under a global actor next to a first answer",
            source: "@MainActor\n@GenerateSpies\nprotocol Badge {\n    nonisolated init(label: String)\n"
                + "    func isVisible() -> Bool\n}",
            message: "'init(label:)' is nonisolated, and the spy's own initializer it calls keeps its first answers "
                + "on the global actor, which it can't set from outside the actor for an answer that isn't "
                + "Sendable; use @GenerateSpies on a class or an actor that conforms to 'Badge' instead",
            line: 4,
            column: 17
        ),
        Refused(
            name: "an init whose spy name another requirement's spy has",
            source: "@GenerateSpies\nprotocol Session {\n    init(user: String)\n    init()\n"
                + "    static func initUser()\n}",
            message: "two requirements would both be spied on as 'initUserSpy'; rename one",
            line: 5,
            column: 17
        ),
    ]

    /// A protocol whose one requirement, the `init` on line 3, is refused at its `init` keyword.
    private static func refusedInit(_ name: String, _ member: String, _ message: String) -> Refused {
        Refused(
            name: name,
            source: "@GenerateSpies\nprotocol Session {\n    \(member)\n}",
            message: message,
            line: 3,
            column: 5
        )
    }
}
