//
//  VerifiesMocks.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

#if canImport(Testing)
import Testing

/// Where an expectation was set: the `expect` call a report points at.
typealias ExpectationSite = SourceLocation
#else
/// No place to point at without Swift Testing, which reports nothing.
typealias ExpectationSite = Never
#endif

/// One thing a strict spy found wrong, in words, with the `expect` it is about; `nil` for a call
/// nobody expected.
struct VerificationProblem {
    /// Which problem this is, so a problem `verify(sourceLocation:)` reported isn't reported again
    /// while another with the same words still is.
    ///
    /// Conformances:
    /// - `Hashable`, so a ledger keeps the reported ones in a set.
    enum ID: Hashable {
        /// The expectation at this position, met by this many calls instead of the times it
        /// wants; a different count is a new problem.
        case unmet(Int, calls: Int)
        /// The call at this position, which no expectation accepts.
        case unexpected(Int)
    }

    /// Which problem this is.
    let id: ID
    /// What went wrong, such as "expected 1 call with 3, got 0 calls".
    let message: String
    /// The `expect` the problem is about.
    let site: ExpectationSite?
}

/// A spy's ledger, seen only as the problems it would report, so `.verifiesMocks` can keep the
/// ledgers of every kind of spy in one list.
protocol VerifiableLedger: AnyObject {
    /// The problems `verify(sourceLocation:)` hasn't reported yet.
    func unreportedProblems() -> [VerificationProblem]
}

/// Conformances:
/// - `VerifiableLedger`, so `.verifiesMocks` lists the ledger of every kind of spy, whatever its
///   input and output, in one registry.
extension Ledger: VerifiableLedger { }

/// The strict spies of one test that runs with `.verifiesMocks`: each one is listed when the
/// test first gives it an expectation, and checked when the test ends.
///
/// Conformances:
/// - `@unchecked Sendable`, so a task local can hold it: its list is read and written only under
///   `lock`, and each ledger in it keeps its own state behind its own lock, the reasoning that
///   makes a spy safe to share.
final class MockRegistry: @unchecked Sendable {
    /// The registry of the test running now; `nil` outside `.verifiesMocks`.
    static let current = TaskLocal<MockRegistry?>(wrappedValue: nil)

    /// Guards `ledgers`.
    private let lock = NSLock()

    /// Every ledger given an expectation in this test, in the order it first was. `var` because
    /// spies are listed as the test runs; only ``register(_:)`` adds.
    private var ledgers: [any VerifiableLedger] = []

    /// Lists `ledger`, unless it is listed already.
    func register(_ ledger: any VerifiableLedger) {
        lock.lock()
        defer {
            lock.unlock()
        }
        if !ledgers.contains(where: { $0 === ledger }) {
            ledgers.append(ledger)
        }
    }

    /// Every listed spy's problems that `verify(sourceLocation:)` hasn't reported.
    func unreportedProblems() -> [VerificationProblem] {
        lock.lock()
        let listed = ledgers
        lock.unlock()
        return listed.flatMap { $0.unreportedProblems() }
    }
}

#if canImport(Testing) && compiler(>=6.1)
/// A test trait that verifies every strict spy when the test ends, so a forgotten `verify()` can
/// no longer pass silently. Use it as ``Testing/Trait/verifiesMocks``.
///
/// Every spy given an expectation during the test, with `expect` or `expectNoCalls()`, is
/// checked: each expectation not met is reported at its `expect` line, and each call nobody
/// expected at the test. A spy with no expectations is never checked, and a problem `verify()`
/// already reported isn't reported again.
///
/// Conformances:
/// - `TestTrait` and `SuiteTrait`, so it goes on a test or on a suite, where every test in the
///   suite is checked on its own.
/// - `TestScoping`, which runs each test with a list of its spies and checks them after.
/// - `Sendable`, which a trait needs: it stores nothing.
public struct VerifiesMocks: TestTrait, SuiteTrait, TestScoping {
    /// Applies to every test in a suite, each checked on its own.
    public var isRecursive: Bool {
        true
    }

    /// Checks each test, and each case of a parameterized test, not a suite as a whole.
    public func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    /// Runs the test, or one case of it, with a list of the spies given an expectation in it,
    /// then reports each of their problems that `verify(sourceLocation:)` didn't. The spies are
    /// checked even when the test throws, and its error then goes on to Swift Testing.
    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let registry = MockRegistry()
        // The spies are checked even when the test throws, so its report shows both.
        defer {
            for problem in registry.unreportedProblems() {
                Issue.record(Comment(rawValue: problem.message), sourceLocation: problem.site ?? test.sourceLocation)
            }
        }
        try await MockRegistry.current.withValue(registry) {
            try await function()
        }
    }
}

/// Constrained to `Self == VerifiesMocks`, so `.verifiesMocks` is found where Swift Testing
/// expects a trait, as its own traits are.
extension Trait where Self == VerifiesMocks {
    /// Verifies every strict spy when each test ends: `@Test(.verifiesMocks)`, or on a suite.
    public static var verifiesMocks: Self {
        VerifiesMocks()
    }
}
#endif
