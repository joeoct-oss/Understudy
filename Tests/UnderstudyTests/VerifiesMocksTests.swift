//
//  VerifiesMocksTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

/// `.verifiesMocks` checks every strict spy when the test ends, so a forgotten `verify()` can't
/// pass silently.
///
/// A problem the trait finds is an issue recorded after the test's body, which no
/// `withKnownIssue` inside the body sees. So the tests of a failing check run their body
/// through the trait's own `provideScope`, as Swift Testing does, inside `withKnownIssue`, and
/// read what it recorded. The tests of a passing check use the trait as a test author does.
@Suite("Mocks that verify themselves")
struct VerifiesMocksTests {
    @Test("An unmet expectation is reported when the test ends, at the expect line")
    func verifiesMocksReportsUnmetExpectation() async throws {
        let expectLine = Spy<Int, Void>()

        let issues = try await issuesAfterTest {
            let analytics = Spy<String, Void>()
            expectLine(#line + 1)
            analytics.expect("checkout")
        }

        let expected = ["expected 1 call with checkout, got 0 calls"]
        #expect(issues.map(\.message) == expected)
        let expectLines: [Int?] = expectLine.calls
        #expect(issues.map(\.line) == expectLines)
    }

    @Test("A call nobody expected is reported at the test")
    func verifiesMocksReportsUnexpectedCall() async throws {
        let test = try #require(Test.current)

        let issues = try await issuesAfterTest {
            let analytics = ThrowingSpy<String, Void>(returning: ())
            analytics.expectNoCalls()
            try analytics("checkout")
        }

        let expected = ["unexpected call with checkout"]
        let testLine: [Int?] = [test.sourceLocation.line]
        #expect(issues.map(\.message) == expected)
        #expect(issues.map(\.line) == testLine)
    }

    @Test("A spy with no expectations is never reported, whatever it was called with", .verifiesMocks)
    func verifiesMocksLeavesLenientSpiesAlone() {
        let analytics = Spy<String, Void>()

        analytics("checkout")
        analytics("refund")

        #expect(analytics.callCount == 2)
    }

    @Test("A problem verify already reported in the test isn't reported again")
    func verifiedByHandIsNotReportedTwice() async throws {
        let issues = try await issuesAfterTest {
            let analytics = Spy<String, Void>()
            analytics.expect("checkout")
            analytics("refund")
            withKnownIssue(isIntermittent: true) {
                analytics.verify()
            }
            analytics("refund")
        }

        let expected = ["unexpected call with refund"]
        #expect(issues.map(\.message) == expected)
    }

    @Test("An expectation with the same words as one verify reported is still reported when unmet")
    func sameWordsAsAReportedProblemStillReported() async throws {
        let issues = try await issuesAfterTest {
            let analytics = Spy<Int, Void>()
            analytics.expect { $0 == 1 }
            withKnownIssue(isIntermittent: true) {
                analytics.verify()
            }
            analytics(1)
            analytics.expect { $0 == 2 }
        }

        let expected = ["expected 1 call with a matching input, got 0 calls"]
        #expect(issues.map(\.message) == expected)
    }

    @Test("An expectation set in a suite's init is checked when the test ends")
    func expectationSetInSuiteInitIsVerified() async throws {
        let issues = try await issuesAfterTest {
            _ = CheckoutSuite()
        }

        let expected = ["expected 1 call with checkout, got 0 calls"]
        #expect(issues.map(\.message) == expected)
    }

    @Test("A spy of a main-actor type, whose input isn't Sendable, is checked too")
    func spyWithNonSendableInputIsVerified() async throws {
        let issues = try await issuesAfterTest { @MainActor in
            let router = Spy<Screen, Void>()
            router.expect(times: 2) { $0.title == "Cart" }
            router(Screen(title: "Cart"))
        }

        let expected = ["expected 2 calls with a matching input, got 1 call"]
        #expect(issues.map(\.message) == expected)
    }

    @Test("A static spy's expectation is checked, next to fresh static spies", .freshSpies(SpyNotifier.self))
    func staticSpyExpectationIsVerified() async throws {
        let issues = try await issuesAfterTest {
            SpyNotifier.notifySpy.expect("sale")
        }

        let expected = ["expected 1 call with sale, got 0 calls"]
        #expect(issues.map(\.message) == expected)
    }

    // Runs `body` as `.verifiesMocks` runs a test, and gives each issue it recorded after the
    // body: its message and its line.
    private func issuesAfterTest(
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws -> [(message: String, line: Int?)] {
        let test = try #require(Test.current)
        let recorded = Spy<Issue, Bool>(returning: true)
        try await withKnownIssue(isIntermittent: true) {
            try await VerifiesMocks.verifiesMocks.provideScope(for: test, testCase: Test.Case.current, performing: body)
        } matching: { issue in
            recorded(issue)
        }
        return recorded.calls.map { issue in
            (issue.comments.map(\.rawValue).joined(), issue.sourceLocation?.line)
        }
    }
}

/// A suite whose `init` sets an expectation, which every test in it must meet.
@Suite("Mocks that verify themselves, set in a suite's init", .verifiesMocks)
struct CheckoutSuite {
    let analytics = Spy<String, Void>()

    init() {
        analytics.expect("checkout")
    }

    @Test("A test in a suite with the trait passes when it meets the expectation set in init")
    func suiteTraitVerifiesEveryTest() {
        analytics("checkout")
    }

    @Test("Each case of a parameterized test meets its own expectation from init", arguments: 1...3)
    func eachParameterizedCaseIsVerifiedAlone(_ round: Int) {
        analytics("checkout")
        #expect(analytics.callCount == 1)
    }
}

/// A screen a router shows: a class, so not `Sendable`.
private final class Screen {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// Sends a notification for the whole app, through a static member.
private protocol Notifier {
    static func notify(_ message: String)
}

/// A notifier whose static calls each test checks.
///
/// Conformances:
/// - `Notifier`, so a test can pass its type where a notifier is expected.
@GenerateSpies
private final class SpyNotifier: Notifier {
    @Spied static func notify(_ message: String)
}
#endif
