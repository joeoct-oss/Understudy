//
//  ThrowingSpy.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

/// A ``Spy`` for a requirement that throws: keeps every input it is called with, in order, and
/// returns or throws as the test scripts it.
///
/// ```swift
/// final class SpyAuthService: AuthService {
///     let signIn = ThrowingSpy<Credentials, Account>(throwing: AuthError.offline)
///
///     func signIn(with credentials: Credentials) async throws -> Account {
///         try signIn(credentials)
///     }
/// }
/// ```
///
/// Conformances:
/// - `@unchecked Sendable` when `Input` and `Output` are, so a `Sendable` double can hold one;
///   every stored value is read and written under a lock.
public final class ThrowingSpy<Input, Output> {
    /// The calls and answers, under one lock.
    private let ledger: Ledger<Input, Result<Output, any Error>>

    /// Every input the spy was called with, oldest first.
    public var calls: [Input] {
        ledger.calls
    }

    /// The number of calls so far.
    public var callCount: Int {
        calls.count
    }

    /// The most recent input, or `nil` before the first call.
    public var lastCall: Input? {
        calls.last
    }

    /// Whether the spy was called at least once.
    public var wasCalled: Bool {
        !calls.isEmpty
    }

    /// Creates a spy that returns `answer` from every call until the test scripts another.
    public init(returning answer: Output) {
        ledger = Ledger(answer: .value(.success(answer)))
    }

    /// Creates a spy that throws `error` from every call until the test scripts another answer.
    public init(throwing error: any Error) {
        ledger = Ledger(answer: .value(.failure(error)))
    }

    /// Creates a spy that answers every call by running `answer` on the call's input.
    public init(answering answer: @escaping @Sendable (Input) throws -> Output) {
        ledger = Ledger(answer: Self.computed(answer))
    }

    /// Turns a throwing answer into one that gives a result, as the ledger keeps them.
    private static func computed(
        _ answer: @escaping @Sendable (Input) throws -> Output
    ) -> Ledger<Input, Result<Output, any Error>>.Answer {
        .computed { input in
            Result {
                try answer(input)
            }
        }
    }

    /// Keeps `input`, then returns or throws the next answer: a queued one if any is left, else
    /// the standing one.
    @discardableResult
    public func callAsFunction(_ input: Input) throws -> Output {
        try ledger.record(input).get()
    }

    /// Returns `answer` from every later call, dropping any answers still queued.
    public func willReturn(_ answer: Output) {
        ledger.answerEveryCall(with: .value(.success(answer)))
    }

    /// Throws `error` from every later call, dropping any answers still queued.
    public func willThrow(_ error: any Error) {
        ledger.answerEveryCall(with: .value(.failure(error)))
    }

    /// Gives `first`, then each of `rest`, to the next calls, once each, and then goes back to the
    /// standing answer. A success is returned and a failure is thrown. Replaces any answers still
    /// queued.
    public func willGive(
        _ first: Result<Output, any Error>,
        then rest: Result<Output, any Error>...
    ) {
        ledger.answerNextCalls(with: CollectionOfOne(first) + rest)
    }

    /// Answers every later call by running `answer` on the call's input, dropping any answers
    /// still queued.
    public func willAnswer(_ answer: @escaping @Sendable (Input) throws -> Output) {
        ledger.answerEveryCall(with: Self.computed(answer))
    }
}

extension ThrowingSpy where Input == Void {
    /// Keeps the call, then returns or throws the next answer, for a requirement that takes
    /// nothing.
    @discardableResult
    public func callAsFunction() throws -> Output {
        try callAsFunction(())
    }
}

extension ThrowingSpy: @unchecked Sendable where Input: Sendable, Output: Sendable { }
