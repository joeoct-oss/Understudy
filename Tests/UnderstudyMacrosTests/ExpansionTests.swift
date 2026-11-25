//
//  ExpansionTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import UnderstudyMacros

/// The code `@Understudy` writes, and how it explains a requirement it can't write.
@Suite("Macro expansion")
struct ExpansionTests {
    @Test
    func classGetsSpiesForwardersAndAnInitializerForEachAnswer() {
        expand(
            """
            @Understudy
            final class SpyCatalog: Catalog {
                @Spied func product(id: Int) -> String
                @Spied func refresh()
            }
            """,
            into: """
            final class SpyCatalog: Catalog {
                func product(id: Int) -> String {
                    return self.__understudy_product(id: id)
                }
                func refresh() {
                    return self.__understudy_refresh()
                }

                let productSpy: Spy<Int, String>

                let refreshSpy = Spy<Void, Void>(returning: ())

                /// Creates the double with the answer each requirement gives until the test scripts another.
                init(product: String) {
                    self.productSpy = .init(returning: product)
                }

                private func __understudy_product(id: Int) -> String {
                    return self.productSpy(id)
                }

                private func __understudy_refresh() -> Void {
                    return self.refreshSpy()
                }
            }
            """
        )
    }

    @Test
    func protocolGetsASpyClassNextToIt() {
        expand(
            """
            @Understudy
            @MainActor
            public protocol Clock {
                func now() -> Int
                func wait(for seconds: Int, tolerance: Int) async throws
            }
            """,
            into: """
            @MainActor
            public protocol Clock {
                func now() -> Int
                func wait(for seconds: Int, tolerance: Int) async throws
            }

            /// A spy for `Clock`, written by `@Understudy`.
            @MainActor
            public final class ClockSpy: Clock {
                public let nowSpy: Spy<Void, Int>

                public let waitSpy = ThrowingSpy<(seconds: Int, tolerance: Int), Void>(returning: ())

                public init(now: Int) {
                    self.nowSpy = .init(returning: now)
                }

                public func now() -> Int {
                    return self.nowSpy()
                }

                public func wait(for seconds: Int, tolerance: Int) async throws {
                    return try self.waitSpy((seconds: seconds, tolerance: tolerance))
                }
            }
            """
        )
    }

    @Test
    func overloadsGetSpiesNamedWithTheirLabels() {
        expand(
            """
            @Understudy
            final class SpyCatalog: Catalog {
                @Spied func remove(id: Int)
                @Spied func remove(named name: String)
            }
            """,
            into: """
            final class SpyCatalog: Catalog {
                func remove(id: Int) {
                    return self.__understudy_remove(id: id)
                }
                func remove(named name: String) {
                    return self.__understudy_remove(named: name)
                }

                let removeIdSpy = Spy<Int, Void>(returning: ())

                let removeNamedSpy = Spy<String, Void>(returning: ())

                private func __understudy_remove(id: Int) -> Void {
                    return self.removeIdSpy(id)
                }

                private func __understudy_remove(named name: String) -> Void {
                    return self.removeNamedSpy(name)
                }
            }
            """
        )
    }

    @Test
    func genericRequirementIsExplained() {
        expand(
            """
            @Understudy
            final class SpyStore: Store {
                @Spied func load<Value>(_ key: String) -> Value
            }
            """,
            into: """
            final class SpyStore: Store {
                func load<Value>(_ key: String) -> Value
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Understudy: 'load' is generic; write its double by hand",
                    line: 3,
                    column: 5
                ),
                DiagnosticSpec(
                    message: "@Understudy: 'load' is generic; write its double by hand",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    @Test
    func protocolPropertyIsExplained() {
        expand(
            """
            @Understudy
            protocol Session {
                var token: String { get }
            }
            """,
            into: """
            protocol Session {
                var token: String { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Understudy: 'Session' has a requirement that isn't a function; write its double by hand, or use @Understudy on a class",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    @Test
    func overloadsThatDifferOnlyInTypesAreExplained() {
        expand(
            """
            @Understudy
            final class SpyLog: Log {
                @Spied func write(_ text: String)
                @Spied func write(_ number: Int)
            }
            """,
            into: """
            final class SpyLog: Log {
                func write(_ text: String) {
                    return self.__understudy_write(text)
                }
                func write(_ number: Int) {
                    return self.__understudy_write(number)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Understudy: two requirements would both be spied on as 'writeSpy'; rename one",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    @Test
    func classWithNothingSpiedIsExplained() {
        expand(
            """
            @Understudy
            final class SpyLog: Log {
                func write(_ text: String) {}
            }
            """,
            into: """
            final class SpyLog: Log {
                func write(_ text: String) {}
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Understudy: mark each requirement to stand in for with @Spied, and give it no body",
                    line: 1,
                    column: 1
                ),
            ]
        )
    }

    private func expand(
        _ source: String,
        into expected: String,
        diagnostics: [DiagnosticSpec] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            source,
            expandedSource: expected,
            diagnostics: diagnostics,
            macroSpecs: Self.macros,
            failureHandler: { failure in
                Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
            }
        )
    }

    private static let macros: [String: MacroSpec] = [
        "Understudy": MacroSpec(type: UnderstudyMacro.self),
        "Spied": MacroSpec(type: SpiedMacro.self),
    ]
}
