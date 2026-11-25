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
    /// How many tasks call at once.
    private static let concurrentCallCount = 1_000

    @Test("A spy keeps every input in order")
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

    @Test("A spy knows when it was never called")
    func knowsWhenItWasNeverCalled() {
        let spy = Spy<Int, Void>()

        #expect(spy.calls.isEmpty)
        #expect(spy.callCount == 0)
        #expect(spy.lastCall == nil)
        #expect(!spy.wasCalled)
    }

    @Test("A spy answers every call with its standing answer")
    func answersWithItsStandingAnswer() {
        let spy = Spy<String, Int>(returning: 7)

        let first = spy("a")
        let second = spy("b")

        #expect(first == 7)
        #expect(second == 7)
    }

    @Test("willReturn replaces the standing answer for later calls")
    func willReturnReplacesTheStandingAnswer() {
        let spy = Spy<String, Int>(returning: 7)
        _ = spy("a")

        spy.willReturn(9)
        let later = spy("b")
        let laterStill = spy("c")

        #expect(later == 9)
        #expect(laterStill == 9)
    }

    @Test("Queued answers come once each, then the standing answer")
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

    @Test("willReturn drops answers still queued")
    func willReturnDropsAnswersStillQueued() {
        let spy = Spy<Void, Int>(returning: 0)
        spy.willReturnNext(1, then: 2)

        spy.willReturn(5)
        let answer = spy()

        #expect(answer == 5)
    }

    @Test("A computed answer sees the input and can be replaced")
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

    @Test("A caller may ignore the answer and the call is still kept")
    func callerMayIgnoreTheAnswer() {
        let spy = Spy<Int, Int>(returning: 1)

        spy(5)

        #expect(spy.lastCall == 5)
    }

    @Test("A spy keeps every call from concurrent tasks")
    func keepsEveryCallFromConcurrentTasks() async {
        let spy = Spy<Int, Void>()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<Self.concurrentCallCount {
                group.addTask {
                    spy(index)
                }
            }
        }

        let expected = Set(0..<Self.concurrentCallCount)
        #expect(spy.callCount == Self.concurrentCallCount)
        #expect(Set(spy.calls) == expected)
    }
}
