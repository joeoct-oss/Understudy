//
//  RecordedTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A `@Recorded` property keeps its gets and sets in a property spy, `$name`, in a double written
/// by hand or by `@GenerateSpies`.
@Suite("Recorded properties")
struct RecordedTests {
    @Test("A Recorded property keeps its gets and sets")
    func recordedPropertyKeepsItsGetsAndSets() {
        let session = HandSession()

        let first = session.user
        session.user = "bo"
        let second = session.user

        let expectedSets = ["bo"]
        #expect(first == "ana")
        #expect(second == "bo")
        #expect(session.$user.sets == expectedSets)
        #expect(session.$user.getCount == 2)
    }

    @Test("A Recorded property answers what the test scripts")
    func recordedPropertyAnswersWhatTheTestScripts() {
        let session = HandSession()

        session.$user.willReturn("bo")

        #expect(session.user == "bo")
        #expect(session.$user.sets.isEmpty)
    }

    @Test("Resetting a Recorded property forgets its gets and sets and keeps its value")
    func recordedPropertyForgetsItsGetsAndSetsOnReset() {
        let session = HandSession()
        session.user = "bo"

        session.$user.reset()

        #expect(session.$user.sets.isEmpty)
        #expect(session.$user.getCount == 0)
        #expect(session.user == "bo")
    }

    @Test("A Recorded property works inside a generated double")
    func recordedPropertyWorksInsideAGeneratedDouble() async throws {
        let session = GeneratedSession(token: "abc")

        session.user = "bo"
        try await session.refresh()

        let expectedUsers = ["bo"]
        #expect(session.token == "abc")
        #expect(session.$user.sets == expectedUsers)
        #expect(session.refreshSpy.callCount == 1)
    }

    @Test("A generated double can have only Recorded properties")
    func aGeneratedDoubleCanHaveOnlyRecordedProperties() {
        let session = RecordedOnlySession()

        session.user = "bo"

        let expectedUsers = ["bo"]
        #expect(session.$user.sets == expectedUsers)
    }
}

/// The signed-in session, as a feature reads and changes it.
private protocol Session: AnyObject {
    var user: String { get set }
}

/// A session written by hand, with its first user at the declaration.
///
/// Conformances:
/// - `Session`, so a test can pass it where a session is expected.
private final class HandSession: Session {
    @Recorded var user = "ana"
}

/// A session that refreshes its token.
private protocol RefreshingSession: Session {
    var token: String { get }
    func refresh() async throws
}

/// A generated session with both kinds of spied property: the token's first value is an
/// initializer argument, and the user's is at the declaration.
///
/// Conformances:
/// - `RefreshingSession`, so a test can pass it where a session is expected.
@GenerateSpies
private final class GeneratedSession: RefreshingSession {
    @SpiedProperty var token: String
    @Recorded var user = "ana"
    @Spied func refresh() async throws
}

/// A generated session whose only spied member is a `@Recorded` property.
///
/// Conformances:
/// - `Session`, so a test can pass it where a session is expected.
@GenerateSpies
private final class RecordedOnlySession: Session {
    @Recorded var user = "ana"
}
