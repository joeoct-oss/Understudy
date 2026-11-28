//
//  NonsendingMemberTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

#if compiler(>=6.2)
/// A gazette opened with a `nonisolated(nonsending)` async init, which its spy keeps as written.
@GenerateSpies
protocol Gazette {
    nonisolated(nonsending) init(edition: String) async
}

/// A newsfeed loaded on the caller's actor.
protocol Newsfeed {
    nonisolated(nonsending) func load(_ section: String) async
}

/// A class double whose spied function keeps `nonisolated(nonsending)` as written.
///
/// Conformances:
/// - `Newsfeed`, so the test reaches it through the protocol.
@GenerateSpies
final class SpyNewsfeed: Newsfeed {
    @Spied nonisolated(nonsending) func load(_ section: String) async
}

/// Doubles whose `nonisolated(nonsending)` members run on the caller's actor and record.
@Suite("Nonsending members")
struct NonsendingMemberTests {
    @Test("A nonsending init and a nonsending spied function record their calls")
    func nonsendingMembersRecord() async throws {
        try await GazetteSpy.withFreshSpies {
            _ = await GazetteSpy(edition: "morning")
            let feed = SpyNewsfeed()

            await feed.load("sport")

            let expectedEditions = ["morning"]
            let expectedSections = ["sport"]
            #expect(GazetteSpy.initSpy.calls == expectedEditions)
            #expect(feed.loadSpy.calls == expectedSections)
        }
    }
}
#endif
