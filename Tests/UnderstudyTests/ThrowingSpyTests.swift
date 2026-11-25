//
//  ThrowingSpyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A throwing spy keeps every call and returns or throws as the test scripts.
@Suite("Throwing spy")
struct ThrowingSpyTests {
    /// The error the tests script.
    ///
    /// Conformances:
    /// - `Error`, so a spy can throw it.
    /// - `Equatable`, so a test can check which error came out.
    private enum LoadError: Error, Equatable {
        case offline
        case notFound
    }

    @Test
    func answersWithItsStandingAnswer() throws {
        let spy = ThrowingSpy<Int, String>(returning: "ok")

        let answer = try spy(1)

        #expect(answer == "ok")
    }

    @Test
    func throwsItsErrorAndStillKeepsTheCall() {
        let spy = ThrowingSpy<Int, String>(throwing: LoadError.offline)

        #expect(throws: LoadError.offline) {
            try spy(4)
        }
        let expected = [4]
        #expect(spy.calls == expected)
    }

    @Test
    func willThrowAndWillReturnReplaceTheStandingAnswer() throws {
        let spy = ThrowingSpy<Int, String>(returning: "ok")

        spy.willThrow(LoadError.notFound)
        #expect(throws: LoadError.notFound) {
            try spy(1)
        }
        spy.willReturn("back")
        let answer = try spy(2)

        #expect(answer == "back")
    }

    @Test
    func givesQueuedResultsInOrderThenTheStandingAnswer() throws {
        let spy = ThrowingSpy<Void, Int>(returning: 0)

        spy.willGive(.success(1), then: .failure(LoadError.offline), .success(2))
        let first = try spy()
        #expect(throws: LoadError.offline) {
            try spy()
        }
        let third = try spy()
        let fourth = try spy()

        #expect(first == 1)
        #expect(third == 2)
        #expect(fourth == 0)
        #expect(spy.callCount == 4)
    }

    @Test
    func computedAnswerSeesTheInput() throws {
        let spy = ThrowingSpy<Int, Int> { input in
            guard input > 0 else {
                throw LoadError.notFound
            }
            return input
        }

        let found = try spy(3)
        #expect(throws: LoadError.notFound) {
            try spy(0)
        }
        spy.willAnswer { input in
            input * 10
        }
        let later = try spy(3)

        #expect(found == 3)
        #expect(later == 30)
    }
}
