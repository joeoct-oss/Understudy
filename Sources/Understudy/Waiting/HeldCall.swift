//
//  HeldCall.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation

/// One async call a test holds: the call waits inside the double until the test resumes it, so the
/// test can check what happens while the work is in flight.
///
/// Get one from a spy's `holdNextCall()` before the call is made. The next async call the spy
/// gets, through `respond(to:)`, then waits:
///
/// ```swift
/// let held = loader.loadSpy.holdNextCall()
/// let task = Task { await screen.load() }
/// let path = await held.arrived()          // the call is in flight
/// #expect(screen.isLoading)
/// held.resume(returning: "data")
/// await task.value
/// ```
///
/// Resuming before the call arrives is fine: the call then returns at once.
///
/// Conformances:
/// - `@unchecked Sendable`, because the test resumes it from its own task while the call waits in
///   another; every stored value is read and written under `lock`, and the input, the answer and
///   the error are all `Sendable`.
public final class HeldCall<Input: Sendable, Output: Sendable, Failure: Error>: @unchecked Sendable {
    /// How the test resumed the call.
    fileprivate enum Decision {
        /// With this result.
        case result(Result<Output, Failure>)
        /// With the answer the spy was scripted to give.
        case scripted
    }

    /// Guards every stored value below.
    private let lock = NSLock()

    /// The call's input, once it arrives.
    private let arrival = Delivery<Input>()

    /// How the test resumed the call, if it did before the call arrived. `var` because the test
    /// sets it once.
    private var decision: Decision?

    /// The waiting call and the answer it was scripted to give, once it arrives and until the test
    /// resumes it. `var` because the call sets it and the resume takes it.
    private var waiting:
        (
            continuation: CheckedContinuation<Result<Output, Failure>, Never>,
            scripted: Result<Output, Failure>
        )?

    /// Created by a spy's `holdNextCall()`.
    init() { }

    /// The held call's input, waiting up to `seconds` for the call to arrive; `nil` when it doesn't
    /// arrive in time.
    @discardableResult
    public func arrived(within seconds: Double = 1) async -> Input? {
        arrival.expire(after: seconds)
        return await arrival.value()
    }

    /// Resumes the call, which returns `answer`.
    public func resume(returning answer: Output) {
        decide(.result(.success(answer)))
    }

    /// Resumes the call with the answer the spy was scripted to give.
    public func resumeWithScriptedAnswer() {
        decide(.scripted)
    }

    /// Takes the call's input and the answer it was scripted to give, and waits until the test
    /// resumes it. Runs in the caller's isolation.
    func arrive(
        isolation: isolated (any Actor)?,
        input: Input,
        scripted: Result<Output, Failure>
    ) async -> Result<Output, Failure> {
        _ = arrival.deliver(input)
        return await withCheckedContinuation { continuation in
            lock.lock()
            guard let decision else {
                waiting = (continuation, scripted)
                lock.unlock()
                return
            }
            lock.unlock()
            continuation.resume(returning: Self.result(of: decision, scripted: scripted))
        }
    }

    /// Resumes the waiting call with `decision`, or keeps it for the call to come. Only the first
    /// decision counts.
    fileprivate func decide(_ decision: Decision) {
        lock.lock()
        guard self.decision == nil else {
            lock.unlock()
            return
        }
        self.decision = decision
        let waiting = waiting
        self.waiting = nil
        lock.unlock()
        if let waiting {
            waiting.continuation.resume(returning: Self.result(of: decision, scripted: waiting.scripted))
        }
    }

    /// The result `decision` gives a call scripted to give `scripted`.
    private static func result(of decision: Decision, scripted: Result<Output, Failure>) -> Result<Output, Failure> {
        switch decision {
        case .result(let result):
            return result
        case .scripted:
            return scripted
        }
    }
}

extension HeldCall where Failure == any Error {
    /// Resumes the call, which throws `error`.
    public func resume(throwing error: any Error) {
        decide(.result(.failure(error)))
    }
}
