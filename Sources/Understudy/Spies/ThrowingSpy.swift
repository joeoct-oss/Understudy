//
//  ThrowingSpy.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if canImport(Testing)
import Testing
#endif

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
    public func willGiveNext(
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

    /// Keeps `input`, then returns or throws the next answer, like calling the spy, for an async
    /// requirement: when the test holds this call with ``holdNextCall()``, it waits until the test
    /// resumes it. Runs in the caller's isolation, so the input never leaves it.
    public func respond(to input: Input, isolation: isolated (any Actor)? = #isolation) async throws -> Output {
        try await ledger.recordHolding(input).get()
    }

    /// Forgets every call and every expectation, so the test can check what happens next on its
    /// own. Keeps what the test scripted: the standing answer, answers queued for the next calls,
    /// and calls the test holds.
    public func reset() {
        ledger.reset()
    }

    /// Runs `body` on every later call, for ``CallOrder``.
    func onEveryCall(_ body: @escaping () -> Void) {
        ledger.watch { _ in
            body()
        }
    }

    #if canImport(Testing)
    /// Expects `times` calls that `matches` accepts; any call by default. The spy becomes strict:
    /// ``verify(sourceLocation:)``, or `.verifiesMocks` when the test ends, then reports each
    /// expectation not met, at `sourceLocation`, and each call no expectation accepts.
    public func expect(
        times: Int = 1,
        where matches: @escaping @Sendable (Input) -> Bool = { _ in true },
        sourceLocation: VerificationLocation = #_sourceLocation
    ) {
        ledger.expect(.init(matches: matches, times: times, description: "a matching input", site: sourceLocation))
    }

    /// Expects no calls at all. The spy becomes strict, so ``verify(sourceLocation:)``, or
    /// `.verifiesMocks` when the test ends, reports every call.
    public func expectNoCalls() {
        ledger.expectNoCalls()
    }

    /// Reports, as a Swift Testing issue at the test's line, every expectation not met and every
    /// call nobody expected, and gives the problems back. Reports nothing for a spy with no
    /// expectations.
    @discardableResult
    public func verify(sourceLocation: VerificationLocation = #_sourceLocation) -> [String] {
        report(ledger.reportProblems(), at: sourceLocation)
    }
    #endif

}

// Constraint: `Output == Void`, because only a requirement that returns nothing has an answer
// the spy can give without the test choosing one.
extension ThrowingSpy where Output == Void {
    /// Creates a spy for a requirement that returns nothing, so it needs no answer. It returns
    /// until the test scripts an error.
    public convenience init() {
        self.init(returning: ())
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

extension ThrowingSpy where Input: Equatable {
    #if canImport(Testing)
    /// Expects `times` calls with `input`. The spy becomes strict: ``verify(sourceLocation:)``,
    /// or `.verifiesMocks` when the test ends, then reports each expectation not met, at
    /// `sourceLocation`, and each call no expectation accepts.
    public func expect(_ input: Input, times: Int = 1, sourceLocation: VerificationLocation = #_sourceLocation) {
        let description = String(describing: input)
        ledger.expect(
            .init(
                matches: { recorded in recorded == input },
                times: times,
                description: description,
                site: sourceLocation
            )
        )
    }
    #endif
}

extension ThrowingSpy where Input: Sendable {
    /// The oldest call not yet given out by this function, from any task, waiting up to `seconds`
    /// for one; `nil` when none comes in time. Each call is given out once, so a call made before
    /// the test starts waiting still counts.
    public func nextCall(within seconds: Double = 1) async -> Input? {
        await ledger.nextCall(within: seconds)
    }
}

extension ThrowingSpy where Input: Sendable, Output: Sendable {
    /// Holds the next async call not yet held: that call waits in ``respond(to:isolation:)`` until
    /// the test resumes it, with an answer, an error or its scripted answer.
    public func holdNextCall() -> HeldCall<Input, Output, any Error> {
        let held = HeldCall<Input, Output, any Error>()
        ledger.holdNextCall { isolation, input, scripted in
            await held.arrive(isolation: isolation, input: input, scripted: scripted)
        }
        return held
    }
}
