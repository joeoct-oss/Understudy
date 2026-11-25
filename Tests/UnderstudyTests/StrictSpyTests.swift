//
//  StrictSpyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A spy with expectations is a strict mock: `verify` reports what was expected and didn't
/// happen, and what happened that nobody expected, as test issues.
@Suite("Strict spies")
struct StrictSpyTests {
    @Test("verify reports nothing when every expectation is met, in any order")
    func verifyReportsNothingWhenEveryExpectationIsMet() {
        let spy = Spy<Int, Void>()
        spy.expect(1)
        spy.expect(2, times: 2)

        spy(2)
        spy(1)
        spy(2)
        let problems = spy.verify()

        #expect(problems.isEmpty)
    }

    @Test("verify reports missing, extra and unexpected calls")
    func verifyReportsMissingExtraAndUnexpectedCalls() throws {
        let loader = ThrowingSpy<String, Int>(returning: 0)
        loader.expect("a")
        loader.expect("b")

        _ = try loader("b")
        _ = try loader("b")
        _ = try loader("c")
        var problems: [String] = []
        withKnownIssue {
            problems = loader.verify()
        }

        let expected = [
            "expected 1 call with a, got 0 calls",
            "expected 1 call with b, got 2 calls",
            "unexpected call with c",
        ]
        #expect(problems == expected)
    }

    @Test("A spy with no expectations stays lenient")
    func spyWithNoExpectationsStaysLenient() {
        let spy = Spy<Int, Void>()

        spy(1)
        let problems = spy.verify()

        #expect(problems.isEmpty)
    }

    @Test("expectNoCalls reports every call")
    func expectNoCallsReportsEveryCall() throws {
        let spy = Spy<Int, Void>()
        let loader = ThrowingSpy<String, Int>(returning: 0)
        spy.expectNoCalls()
        loader.expectNoCalls()

        spy(1)
        _ = try loader("a")
        var problems: [String] = []
        withKnownIssue {
            problems = spy.verify() + loader.verify()
        }

        let expected = [
            "unexpected call with 1",
            "unexpected call with a",
        ]
        #expect(problems == expected)
    }

    @Test("Expectations can match inputs that aren't Equatable")
    func expectationsCanMatchInputsThatAreNotEquatable() throws {
        let save = Spy<(path: String, force: Bool), Void>()
        let loader = ThrowingSpy<(path: String, force: Bool), Int>(returning: 0)
        save.expect { $0.force }
        loader.expect(times: 2) { !$0.force }

        save((path: "a", force: true))
        _ = try loader((path: "b", force: false))
        _ = try loader((path: "c", force: false))
        let problems = save.verify() + loader.verify()

        #expect(problems.isEmpty)
    }
}
