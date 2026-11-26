//
//  FreshSpies.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// A double with static spies, which ``GenerateSpies()`` writes for its static requirements: they
/// live in a box held in a task local, so each test can run with a box of its own.
public protocol StaticSpies {
    /// Runs a test with a fresh box of this double's static spies, which every task the test
    /// starts sees in place of the shared one. A closure, so a test trait can keep it without
    /// keeping the double's type.
    static var withFreshSpies: @Sendable (_ test: () async throws -> Void) async throws -> Void { get }
}

#if canImport(Testing) && compiler(>=6.1)
import Testing

/// A test trait that runs each test with fresh static spies for the doubles it names, so parallel
/// tests never share a static spy's calls or answers. Use it as ``Testing/Trait/freshSpies(_:)``.
///
/// Conformances:
/// - `TestTrait` and `SuiteTrait`, so it goes on a test or on a suite, where every test in the
///   suite gets its own spies.
/// - `TestScoping`, which runs each test inside the fresh spies.
/// - `Sendable`: it stores only `@Sendable` closures that set up the spies.
public struct FreshSpies: TestTrait, SuiteTrait, TestScoping {
    /// Runs a test inside fresh spies for one double.
    typealias Freshener = @Sendable (_ test: () async throws -> Void) async throws -> Void

    /// One per double the trait names, each running a test inside fresh spies for its double.
    private let fresheners: [Freshener]

    /// Applies to every test in a suite, each with its own spies.
    public var isRecursive: Bool {
        true
    }

    init(_ fresheners: [Freshener]) {
        self.fresheners = fresheners
    }

    /// Runs `test` inside each of `fresheners`, one inside another.
    private static func run(_ test: () async throws -> Void, inside fresheners: ArraySlice<Freshener>) async throws {
        guard let first = fresheners.first else {
            return try await test()
        }
        try await first {
            try await run(test, inside: fresheners.dropFirst())
        }
    }

    /// Provides the fresh spies around each test, not around a suite as a whole.
    public func scopeProvider(for _: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await Self.run(function, inside: fresheners[...])
    }
}

extension Trait where Self == FreshSpies {
    /// Runs each test with fresh static spies for `doubles`, so parallel tests never see each
    /// other's calls or answers: `@Test(.freshSpies(SpyClock.self))`, or on a suite.
    public static func freshSpies(_ doubles: any StaticSpies.Type...) -> Self {
        FreshSpies(doubles.map { $0.withFreshSpies })
    }
}
#endif
