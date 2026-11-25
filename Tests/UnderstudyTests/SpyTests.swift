//
//  SpyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A spy keeps every call and answers as the test scripts.
@Suite("Spy")
struct SpyTests {
    @Test
    func keepsEveryInputInOrder() {
        let spy = Spy<Int, Void>()

        spy(1)
        spy(2)
        spy(3)

        let expected = [1, 2, 3]
        #expect(spy.calls == expected)
        #expect(spy.callCount == 3)
        #expect(spy.lastCall == 3)
        #expect(spy.wasCalled)
    }

    @Test
    func knowsWhenItWasNeverCalled() {
        let spy = Spy<Int, Void>()

        #expect(spy.calls.isEmpty)
        #expect(spy.callCount == 0)
        #expect(spy.lastCall == nil)
        #expect(!spy.wasCalled)
    }

    @Test
    func answersWithItsStandingAnswer() {
        let spy = Spy<String, Int>(returning: 7)

        let first = spy("a")
        let second = spy("b")

        #expect(first == 7)
        #expect(second == 7)
    }

    @Test
    func willReturnReplacesTheStandingAnswer() {
        let spy = Spy<String, Int>(returning: 7)
        _ = spy("a")

        spy.willReturn(9)
        let later = spy("b")
        let laterStill = spy("c")

        #expect(later == 9)
        #expect(laterStill == 9)
    }

    @Test
    func queuedAnswersComeOnceEachThenTheStandingAnswer() {
        let spy = Spy<Void, Int>(returning: 0)

        spy.willReturnNext(1, then: 2, 3)
        let answers = (0..<5).map { _ in
            spy()
        }

        let expected = [1, 2, 3, 0, 0]
        #expect(answers == expected)
        #expect(spy.callCount == 5)
    }

    @Test
    func willReturnDropsAnswersStillQueued() {
        let spy = Spy<Void, Int>(returning: 0)
        spy.willReturnNext(1, then: 2)

        spy.willReturn(5)
        let answer = spy()

        #expect(answer == 5)
    }

    @Test
    func computedAnswerSeesTheInput() {
        let spy = Spy<Int, Int> { input in
            input * 2
        }

        let first = spy(2)
        spy.willAnswer { input in
            input + 100
        }
        let second = spy(2)

        #expect(first == 4)
        #expect(second == 102)
    }

    @Test
    func callerMayIgnoreTheAnswer() {
        let spy = Spy<Int, Int>(returning: 1)

        spy(5)

        #expect(spy.lastCall == 5)
    }
}
