//
//  ResetTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A reset spy forgets what happened and keeps what the test scripted, so a test can check one
/// step at a time.
@Suite("Reset")
struct ResetTests {
    @Test
    func resetForgetsCallsAndKeepsTheAnswers() throws {
        let spy = Spy<Int, String>(returning: "standing")
        let loader = ThrowingSpy<String, Int>(returning: 0)
        spy.willReturnNext("queued")
        loader.willThrow(LoadError.offline)
        spy(1)
        _ = try? loader("a")

        spy.reset()
        loader.reset()
        let answer = spy(2)

        let expectedCalls = [2]
        #expect(spy.calls == expectedCalls)
        #expect(answer == "standing")
        #expect(loader.calls.isEmpty)
        #expect(throws: LoadError.offline) {
            try loader("b")
        }
    }

    @Test
    func resetDropsExpectationsSoTheSpyIsLenientAgain() throws {
        let spy = Spy<Int, Void>()
        let loader = ThrowingSpy<String, Int>(returning: 0)
        spy.expectNoCalls()
        loader.expect("a")

        spy.reset()
        loader.reset()
        spy(1)
        let problems = spy.verify() + loader.verify()

        #expect(problems.isEmpty)
    }

    @Test
    func nextCallStartsAgainFromTheFirstCallAfterTheReset() async {
        let spy = Spy<Int, Void>()
        spy(1)
        _ = await spy.nextCall()

        spy.reset()
        spy(2)
        let next = await spy.nextCall()

        #expect(next == 2)
    }

    @Test
    func resetPropertyForgetsGetsAndSetsAndKeepsItsValue() {
        let token = PropertySpy<String>(returning: "a")
        token.set("b")
        _ = token.get()

        token.reset()

        #expect(token.getCount == 0)
        #expect(token.sets.isEmpty)
        #expect(token.get() == "b")
    }

    /// The error the tests script.
    ///
    /// Conformances:
    /// - `Error`, so a spy can throw it.
    /// - `Equatable`, so a test can check which error came out.
    private enum LoadError: Error, Equatable {
        case offline
    }
}
