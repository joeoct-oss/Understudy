//
//  RefusedShapes.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// The doubles the macros refuse for their shape, or for where a marker sits, rather than for one
/// member they can't write.
extension ExpansionTests {
    /// Each refused shape, with the message the macros give and the line and column it points to.
    static let refusedShapes: [Refused] = [
        Refused(
            name: "overloads that differ only in their types",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String)
                    @Spied func write(_ number: Int)
                }
                """,
            message: "two requirements would both be spied on as 'writeSpy'; rename one",
            line: 4,
            column: 17
        ),
        Refused(
            name: "a requirement with a body",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String) {}
                }
                """,
            message: "'write' is @Spied, so give it no body",
            line: 3,
            column: 17
        ),
        Refused(
            name: "a class with nothing spied",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "mark each function to stand in for with @Spied and give it no body, "
                + "each property with @SpiedProperty or @Recorded, and the get and set of each subscript with @Spied",
            line: 1,
            column: 1
        ),
        Refused(
            name: "@Recorded in a Sendable class",
            source: """
                @GenerateSpies
                final class SpySession: Session, Sendable {
                    @Recorded var user = "ana"
                }
                """,
            message: "'user' is @Recorded, which a Sendable class can't hold, because a wrapped property's "
                + "storage is a var; use @SpiedProperty",
            line: 3,
            column: 19
        ),
        Refused(
            name: "@Recorded in an actor",
            source: """
                @GenerateSpies
                actor SpyStore: Store {
                    @Recorded var count = 0
                    @Spied func save(_ item: String) async throws
                }
                """,
            message: "'count' is @Recorded, whose spy a test can't read on an actor without await; "
                + "use @SpiedProperty",
            line: 3,
            column: 19
        ),
        Refused(
            name: "a struct",
            source: """
                @GenerateSpies
                struct SpyLog: Log {
                    func write(_ text: String) {}
                }
                """,
            message: "attach it to a class, an actor or a protocol",
            line: 1,
            column: 1
        ),
        Refused(
            name: "@Spied outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied in a class with another attribute and no @GenerateSpies",
            source: """
                @MainActor
                final class Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 3,
            column: 5
        ),
        Refused(
            name: "@SpiedProperty outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    @SpiedProperty var token: String?
                }
                """,
            message: "@SpiedProperty needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@SpiedProperty on a subscript",
            source: """
                final class Lines {
                    @SpiedProperty subscript(line: Int) -> String { "" }
                }
                """,
            message: "@SpiedProperty goes on a var",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied in a struct",
            source: """
                struct Lonely {
                    @Spied func ping()
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 5
        ),
        Refused(
            name: "@Spied on something that isn't a function",
            source: """
                @GenerateSpies
                final class SpyLog: Log {
                    @Spied func write(_ text: String)
                    @Spied init() {}
                }
                """,
            message: "@Spied goes on a function, or on the get and set of a subscript",
            line: 4,
            column: 5
        ),
        Refused(
            name: "a protocol initializer",
            source: """
                @GenerateSpies
                protocol Session {
                    init(user: String)
                }
                """,
            message: "'Session' has a requirement that is not a function, a property or a subscript; "
                + "write its double by hand, or use @GenerateSpies on a class or an actor",
            line: 3,
            column: 5
        ),
        Refused(
            name: "a protocol subscript that throws",
            source: """
                @GenerateSpies
                protocol Session {
                    subscript(key: String) -> String { get throws }
                }
                """,
            message: "'subscript' is async or throws; write its double by hand",
            line: 3,
            column: 5
        ),
        Refused(
            name: "an async protocol subscript",
            source: """
                @GenerateSpies
                protocol Session {
                    subscript(key: String) -> String { get async }
                }
                """,
            message: "'subscript' is async or throws; write its double by hand",
            line: 3,
            column: 5
        ),
        Refused(
            name: "a @Spied subscript outside a @GenerateSpies class",
            source: """
                final class Lonely {
                    subscript(index: Int) -> Int { @Spied get {} }
                }
                """,
            message: "@Spied needs @GenerateSpies on the class or actor it is in",
            line: 2,
            column: 36
        ),
        Refused(
            name: "@Spied on the get of a property",
            source: """
                @GenerateSpies
                final class Lines {
                    @Spied func clear()
                    var count: Int { @Spied get {} }
                }
                """,
            message: "@Spied goes on a function, or on the get and set of a subscript",
            line: 4,
            column: 22
        ),
    ]
}
