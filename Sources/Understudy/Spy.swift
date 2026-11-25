//
//  Spy.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if canImport(Testing)
import Testing
#endif

/// Stands in for one requirement of a test double: keeps every input it is called with, in order,
/// and answers each call as the test scripts it.
///
/// A test double holds one spy per requirement and calls it from the requirement's body:
///
/// ```swift
/// final class SpyCatalog: ProductCatalog {
///     let productByID = Spy<Int, Product?>(returning: nil)
///
///     func product(id: Int) -> Product? {
///         productByID(id)
///     }
/// }
/// ```
///
/// The test scripts the answers with ``willReturn(_:)``, ``willReturnNext(_:then:)`` or
/// ``willAnswer(_:)``, and checks the calls with ``calls``. A requirement with several parameters
/// records a labelled tuple, such as `Spy<(id: Int, force: Bool), Void>`.
///
/// A spy carries no actor, so it works in a main-actor double and in a `Sendable` one alike.
///
/// Conformances:
/// - `@unchecked Sendable` when `Input` and `Output` are, so a `Sendable` double can hold one;
///   every stored value is read and written under a lock.
public final class Spy<Input, Output> {
    /// The calls and answers, under one lock.
    private let ledger: Ledger<Input, Output>

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

    /// Creates a spy that answers every call with `answer` until the test scripts another.
    public init(returning answer: Output) {
        ledger = Ledger(answer: .value(answer))
    }

    /// Creates a spy that answers every call by running `answer` on the call's input.
    public init(answering answer: @escaping @Sendable (Input) -> Output) {
        ledger = Ledger(answer: .computed(answer))
    }

    /// Keeps `input` and gives the next answer: a queued one if any is left, else the standing one.
    @discardableResult
    public func callAsFunction(_ input: Input) -> Output {
        ledger.record(input)
    }

    /// Answers every later call with `answer`, dropping any answers still queued.
    public func willReturn(_ answer: Output) {
        ledger.answerEveryCall(with: .value(answer))
    }

    /// Answers the next calls with `first`, then each of `rest`, once each, and then goes back to
    /// the standing answer. Replaces any answers still queued.
    public func willReturnNext(_ first: Output, then rest: Output...) {
        ledger.answerNextCalls(with: CollectionOfOne(first) + rest)
    }

    /// Answers every later call by running `answer` on the call's input, dropping any answers
    /// still queued.
    public func willAnswer(_ answer: @escaping @Sendable (Input) -> Output) {
        ledger.answerEveryCall(with: .computed(answer))
    }

    /// Keeps `input` and gives the next answer, like calling the spy, for an async requirement:
    /// when the test holds this call with ``holdNextCall()``, it waits until the test resumes it.
    /// Runs in the caller's isolation, so the input never leaves it.
    public func respond(to input: Input, isolation: isolated (any Actor)? = #isolation) async -> Output {
        await ledger.recordHolding(input)
    }

    /// Runs `body` on every later call, for ``CallOrder``.
    func onEveryCall(_ body: @escaping () -> Void) {
        ledger.watch { _ in
            body()
        }
    }

    /// Expects `times` calls that `matches` accepts; any call by default. The spy becomes strict:
    /// ``verify(sourceLocation:)`` then reports each expectation not met and each call no
    /// expectation accepts.
    public func expect(times: Int = 1, where matches: @escaping @Sendable (Input) -> Bool = { _ in true }) {
        ledger.expect(.init(matches: matches, times: times, description: "a matching input"))
    }

    /// Expects no calls at all. The spy becomes strict, so ``verify(sourceLocation:)`` reports
    /// every call.
    public func expectNoCalls() {
        ledger.expectNoCalls()
    }

    #if canImport(Testing)
    /// Reports, as a Swift Testing issue at the test's line, every expectation not met and every
    /// call nobody expected, and gives the problems back. Reports nothing for a spy with no
    /// expectations.
    @discardableResult
    public func verify(sourceLocation: VerificationLocation = #_sourceLocation) -> [String] {
        report(ledger.problems(), at: sourceLocation)
    }
    #endif

}

extension Spy where Output == Void {
    /// Creates a spy for a requirement that returns nothing, so it needs no answer.
    public convenience init() {
        self.init(returning: ())
    }
}

extension Spy where Input == Void {
    /// Keeps the call and gives the next answer, for a requirement that takes nothing.
    @discardableResult
    public func callAsFunction() -> Output {
        callAsFunction(())
    }
}

extension Spy: @unchecked Sendable where Input: Sendable, Output: Sendable { }

extension Spy where Input: Equatable {
    /// Expects `times` calls with `input`. The spy becomes strict: ``verify(sourceLocation:)``
    /// then reports each expectation not met and each call no expectation accepts.
    public func expect(_ input: Input, times: Int = 1) {
        ledger.expect(.init(matches: { $0 == input }, times: times, description: String(describing: input)))
    }
}

extension Spy where Input: Sendable {
    /// The oldest call not yet given out by this function, from any task, waiting up to `seconds`
    /// for one; `nil` when none comes in time. Each call is given out once, so a call made before
    /// the test starts waiting still counts.
    public func nextCall(within seconds: Double = 1) async -> Input? {
        await ledger.nextCall(within: seconds)
    }
}

extension Spy where Input: Sendable, Output: Sendable {
    /// Holds the next async call not yet held: that call waits in ``respond(to:isolation:)`` until
    /// the test resumes it.
    public func holdNextCall() -> HeldCall<Input, Output, Never> {
        let held = HeldCall<Input, Output, Never>()
        ledger.holdNextCall { isolation, input, scripted in
            switch await held.arrive(isolation: isolation, input: input, scripted: .success(scripted)) {
            case .success(let answer):
                return answer
            }
        }
        return held
    }
}
