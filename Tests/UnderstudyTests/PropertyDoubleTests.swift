//
//  PropertyDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How a generated double's spied properties behave once the compiler builds it.
@Suite("Generated doubles of properties")
struct PropertyDoubleTests {
    @Test("Spied properties keep every set and answer gets")
    func propertiesKeepEverySetAndAnswerGets() {
        var expired = false
        let session = SpySession(user: "ana", onExpire: { expired = true })

        session.token = "abc"
        session.token = nil
        let user = session.user
        session.onExpire()

        let expectedTokens: [String?] = ["abc", nil]
        #expect(session.tokenSpy.sets == expectedTokens)
        #expect(session.token == nil)
        #expect(user == "ana")
        #expect(session.userSpy.getCount == 1)
        #expect(expired)
    }

    @Test("A spied property declared with a value starts with it")
    func spiedPropertyWithAValueStartsWithIt() {
        let session = SpyProfile()

        let user = session.user
        session.user = "bo"

        let expectedUsers = ["bo"]
        #expect(user == "ana")
        #expect(session.userSpy.sets == expectedUsers)
        #expect(session.user == "bo")
    }

    @Test("A spied property with a value keeps every set in a Sendable class")
    func spiedPropertyWithAValueWorksInASendableClass() async {
        let account = SpyAccount()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    account.user = "user \(index)"
                }
            }
        }

        #expect(account.userSpy.sets.count == 10)
    }

    @Test("A spied property with a value keeps its sets in an actor")
    func spiedPropertyWithAValueWorksInAnActor() async {
        let counter = SpyCounter()

        await counter.bump()

        let expectedCounts = [1]
        #expect(counter.countSpy.sets == expectedCounts)
        #expect(counter.countSpy.value == 1)
    }
}

/// The signed-in session, as a feature reads and changes it.
private protocol Session: AnyObject {
    var token: String? { get set }
    var user: String { get }
    var onExpire: () -> Void { get }
}

/// A session whose values the test chose, and that keeps every token set.
///
/// Conformances:
/// - `Session`, so a test can pass it where a session is expected.
@GenerateSpies
private final class SpySession: Session {
    @SpiedProperty var token: String?
    @SpiedProperty var user: String
    @SpiedProperty var onExpire: () -> Void
}

/// A profile a screen shows and edits.
private protocol Profile: AnyObject {
    var user: String { get set }
}

/// A profile whose user starts as "ana", so the test makes it with no arguments.
///
/// Conformances:
/// - `Profile`, so a test can pass it where a profile is expected.
@GenerateSpies
private final class SpyProfile: Profile {
    @SpiedProperty var user: String = "ana"
}

/// Counts on its own actor.
private protocol Counter: Actor {
    var count: Int { get set }
}

/// A counter that starts at 0, an actor like the real one.
///
/// Conformances:
/// - `Counter`, so a test can pass it where a counter is expected.
@GenerateSpies
private actor SpyCounter: Counter {
    @SpiedProperty var count: Int = 0
    // Bumps the count from inside the actor, as the code under test would.
    func bump() {
        count += 1
    }
}

/// A signed-in account that any task may read.
private protocol Account: Sendable {
    var user: String { get set }
}

/// A sendable account whose user starts as "ana", which `@Recorded` can't spy on.
///
/// Conformances:
/// - `Account`, so a test can pass it where an account is expected.
/// - `Sendable`: it stores only its spies, which are `Sendable`.
@GenerateSpies
private final class SpyAccount: Account, Sendable {
    @SpiedProperty var user: String = "ana"
}
