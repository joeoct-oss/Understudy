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
    @Test("Reset forgets calls and keeps the standing answer and the answers still queued")
    func resetForgetsCallsAndKeepsTheAnswers() throws {
        let spy = Spy<Int, String>(returning: "standing")
        let loader = ThrowingSpy<String, Int>(returning: 0)
        spy.willReturnNext("first", then: "second")
        loader.willThrow(LoadError.offline)
        spy(1)
        _ = try? loader("a")

        spy.reset()
        loader.reset()
        let answers = [spy(2), spy(3)]

        let expectedCalls = [2, 3]
        let expectedAnswers = ["second", "standing"]
        #expect(spy.calls == expectedCalls)
        #expect(answers == expectedAnswers)
        #expect(loader.calls.isEmpty)
        #expect(throws: LoadError.offline) {
            try loader("b")
        }
    }

    @Test("Reset drops expectations, so the spy is lenient again")
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

    @Test("nextCall starts again from the first call after a reset")
    func nextCallStartsAgainFromTheFirstCallAfterTheReset() async {
        let spy = Spy<Int, Void>()
        spy(1)
        _ = await spy.nextCall()

        spy.reset()
        spy(2)
        let next = await spy.nextCall()

        #expect(next == 2)
    }

    @Test("Resetting a property spy forgets gets and sets and keeps its value")
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
