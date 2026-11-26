//
//  TraitBenchmarks.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A double with a static requirement, so `.freshSpies` has spies to make fresh.
@GenerateSpies
protocol Beacon {
    static func signal() -> Int
}

/// What each trait adds to a test that does nothing, measured inside a running test, where the
/// trait gets the real test and test case, as Swift Testing gives them.
@Suite("Traits", .serialized)
struct TraitBenchmarks {
    /// The empty tests each run scopes.
    private static let scopes = 1_000

    @Test("An empty test with no trait, with .freshSpies and with .verifiesMocks")
    func traitScopes() async throws {
        let test = try #require(Test.current)
        let testCase = Test.Case.current
        try await Measure.time("Traits", "An empty test, no trait", count: Self.scopes, unit: "µs") {
            for _ in 0..<Self.scopes {
                try await Self.empty()
            }
        }
        let fresh: FreshSpies = .freshSpies(BeaconSpy.self)
        try await Measure.time("Traits", "An empty test with `.freshSpies`", count: Self.scopes, unit: "µs") {
            for _ in 0..<Self.scopes {
                try await fresh.provideScope(for: test, testCase: testCase, performing: Self.empty)
            }
        }
        let verifies: VerifiesMocks = .verifiesMocks
        try await Measure.time("Traits", "An empty test with `.verifiesMocks`", count: Self.scopes, unit: "µs") {
            for _ in 0..<Self.scopes {
                try await verifies.provideScope(for: test, testCase: testCase, performing: Self.empty)
            }
        }
    }

    /// A test body that does nothing.
    @Sendable
    private static func empty() async throws { }
}
