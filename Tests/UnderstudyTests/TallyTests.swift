//
//  TallyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Foundation
import Testing
@testable import Understudy

@Suite("Tally")
struct TallyTests {
    @Test
    func addCounts() async throws {
        let tally = Tally()

        tally.add("a")
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(tally.keys() == ["a"])
    }

    @Test("Test that the report works")
    func report() {
        let tally = Tally()
        tally.add("a")
        tally.add("b")

        #expect(tally.report(sorted: true, verbose: false) == "a=1\nb=1\n")
        #expect(tally.description.count > 0)
    }

    @Test("A spy remembers how often and in which order it was called")
    func spyCountAndOrder() {
        let spy = Spy<Int, Void>()

        spy(1)
        spy(2)

        let expected = [1, 2]
        #expect(spy.callCount == 2)
        #expect(spy.calls == expected)
    }
}
