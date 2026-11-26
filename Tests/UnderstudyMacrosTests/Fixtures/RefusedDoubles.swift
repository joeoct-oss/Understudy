//
//  RefusedDoubles.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// Every shape of double the macros must refuse, with the message and the place it points to.
extension ExpansionTests {
    static let refused: [Refused] = [
        refusedRequirement(
            "a generic with a where clause",
            "func load<Value>(_ key: String) -> Value where Value: Codable",
            "'load' has a where clause; write its double by hand",
            column: 17
        ),
        refusedRequirement("a generic parameter pack", "func load<each Value>(_ keys: repeat each Value)",
                           "'load' takes a parameter pack; write its double by hand", column: 17),
        refusedRequirement("a generic inside a closure", "func save<Value>(_ handler: (Value) -> Void)",
                           "'save' uses 'Value' inside another type; write its double by hand", column: 40),
        refusedRequirement("a generic inside a tuple", "func pair<Value>(_ both: (Value, Value))",
                           "'pair' uses 'Value' inside another type; write its double by hand", column: 37),
        refusedRequirement("a generic dictionary key", "func index<Key: Hashable>(_ map: [Key: Int])",
                           "'index' uses 'Key' inside another type; write its double by hand", column: 45),
        refusedRequirement(
            "a generic inside another generic type",
            "func load<Value>(_ key: String) -> Result<Value, Error>",
            "'load' uses 'Value' inside another type; write its double by hand",
            column: 47
        ),
        refusedRequirement("a static requirement with no obvious answer", "static func now() -> Date",
                           "'now' is static, so no initializer takes its first answer, and 'Date' has no "
                               + "obvious one; make it optional, or write its double by hand", column: 24),
        refusedRequirement("a mutating requirement", "mutating func reset()",
                           "'reset' is mutating; @GenerateSpies writes classes and actors", column: 26),
        refusedRequirement("a typed throws of a generic parameter", "func load<Failure: Error>() throws(Failure)",
                           "'load' throws its generic parameter 'Failure'; write its double by hand", column: 47),
        refusedRequirement("rethrows", "func each(_ body: () throws -> Void) rethrows",
                           "'each' rethrows; write its double by hand", column: 17),
        refusedRequirement("a parameter with no name", "func move(_: Int)",
                           "'move' has a parameter with no name; name it", column: 22),
        refusedRequirement("an opaque answer", "func body() -> some View",
                           "'body' returns an opaque type; write its double by hand", column: 17),
        refusedRequirement("an inout parameter", "func bump(_ value: inout Int)",
                           "'bump' takes an inout parameter; write its double by hand", column: 22),
        refusedRequirement("an autoclosure", "func log(_ text: @autoclosure () -> String)",
                           "'log' takes an autoclosure; write its double by hand", column: 21),
        refusedProperty("a let", "let token: String",
                        "'token' is a let; declare it as a var", column: 24),
        refusedProperty("a property with accessors", "var token: String { \"\" }",
                        "'token' is @SpiedProperty, so give it no accessors", column: 24),
        refusedProperty("a static property with no obvious value", "static var zone: TimeZone",
                        "'zone' is static, so no initializer takes its first answer, and 'TimeZone' has no "
                            + "obvious one; make it optional, or write its double by hand", column: 31),
        refusedProperty("a property with no type", "var token",
                        "'token' has no type; write its type", column: 24),
        refusedProperty("a tuple of properties", "var (first, second): (Int, Int)",
                        "declare one property at a time", column: 24),
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
        refusedRequirement("a static subscript", "static subscript(index: Int) -> Int { @Spied get {} }",
                           "'subscript' is static; write its double by hand", column: 12, marker: ""),
        refusedRequirement("a generic subscript", "subscript<Value>(key: String) -> Value { @Spied get {} }",
                           "'subscript' is generic; write its double by hand", column: 5, marker: ""),
        refusedRequirement("a subscript with a body", "subscript(index: Int) -> Int { @Spied get { 0 } }",
                           "'subscript' has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                               + "or { @Spied get {} } with no set", column: 5, marker: ""),
        refusedRequirement("an unmarked accessor", "subscript(index: Int) -> Int { @Spied get {} set {} }",
                           "'subscript' has @Spied accessors, so write it as { @Spied get {} @Spied set {} }, "
                               + "or { @Spied get {} } with no set", column: 5, marker: ""),
        refusedRequirement("a subscript index with no name", "subscript(_: Int) -> Int { @Spied get {} }",
                           "'subscript' has an index with no name; name it", column: 15, marker: ""),
        refusedRequirement("an inout subscript index", "subscript(index: inout Int) -> Int { @Spied get {} }",
                           "'subscript' takes an inout parameter; write its double by hand", column: 15, marker: ""),
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
        refusedProtocol(
            "an associated type with a where clause",
            "protocol Repository {\n    associatedtype Item where Item: Codable",
            "'Item' has a where clause, which a generic parameter can't keep; "
                + "\(classForm) 'Repository' instead",
            line: 3,
            column: 20
        ),
        refusedProtocol(
            "a protocol where clause next to an associated type",
            "protocol Repository where Item: Codable {\n    associatedtype Item",
            "'Repository' has a where clause, which the spy's generic parameters can't keep; "
                + "\(classForm) 'Repository' instead",
            line: 2,
            column: 21
        ),
        refusedProtocol(
            "a static requirement next to an associated type",
            "protocol Repository {\n    associatedtype Item\n    static func make() -> Item?",
            "'make' is static, and a spy with associated types is generic, so it can't keep a static "
                + "spy; \(classForm) 'Repository' instead",
            line: 4,
            column: 17
        ),
        refusedProtocol(
            "a standard library parent",
            "protocol Account: Identifiable {",
            "'Account' inherits 'Identifiable', which has no spy to forward to; \(classForm) 'Account' instead",
            line: 2,
            column: 19
        ),
        refusedProtocol(
            "a parent written with its associated types",
            "protocol Shelf: Box<Int> {",
            "'Shelf' inherits 'Box<Int>', which has associated types, so its spy can't forward to "
                + "that one's spy; \(classForm) 'Shelf' instead",
            line: 2,
            column: 17
        ),
        refusedProtocol(
            "an actor protocol that inherits another",
            "protocol Store: Actor, Base {",
            "'Store' is an actor protocol that inherits 'Base', which its spy can't forward to across "
                + "the actor; \(classForm) 'Store' instead",
            line: 2,
            column: 24
        ),
    ]

    /// What every refusal of a protocol the class form can write says to do instead.
    private static let classForm = "use @GenerateSpies on a class or an actor that conforms to"

    /// A protocol whose declaration starts with `opening`, and which has one function, that the
    /// macros can't write.
    private static func refusedProtocol(
        _ name: String,
        _ opening: String,
        _ message: String,
        line: Int,
        column: Int
    ) -> Refused {
        Refused(
            name: name,
            source: """
                @GenerateSpies
                \(opening)
                    func ping()
                }
                """,
            message: message,
            line: line,
            column: column
        )
    }

    /// A double whose one property, on line 3, the macros can't write.
    private static func refusedProperty(
        _ name: String,
        _ property: String,
        _ message: String,
        column: Int
    ) -> Refused {
        refusedRequirement(name, property, message, column: column, marker: "@SpiedProperty")
    }

    /// A double whose one requirement, on line 3, the macros can't write.
    private static func refusedRequirement(
        _ name: String,
        _ requirement: String,
        _ message: String,
        column: Int,
        marker: String = "@Spied"
    ) -> Refused {
        Refused(
            name: name,
            source: """
                @GenerateSpies
                final class SpyStore: Store {
                    \(marker.isEmpty ? "" : marker + " ")\(requirement)
                }
                """,
            message: message,
            line: 3,
            column: column
        )
    }
}
