//
//  PropertySpyTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A property spy answers gets, counts them, and keeps every set, as a real property would.
@Suite("Property spy")
struct PropertySpyTests {
    @Test
    func getsAnswerTheScriptedValueAndAreCounted() {
        let token = PropertySpy<String?>(returning: "abc")

        let first = token.get()
        let second = token.get()

        #expect(first == "abc")
        #expect(second == "abc")
        #expect(token.getCount == 2)
        #expect(token.sets.isEmpty)
    }

    @Test
    func setsAreKeptAndChangeWhatLaterGetsAnswer() {
        let token = PropertySpy<String?>(returning: nil)

        token.set("one")
        token.set(nil)
        token.set("two")
        let read = token.get()

        let expected: [String?] = ["one", nil, "two"]
        #expect(token.sets == expected)
        #expect(read == "two")
        #expect(token.value == "two")
    }

    @Test
    func willReturnChangesTheAnswerWithoutCountingAsASet() {
        let count = PropertySpy<Int>(returning: 0)

        count.willReturn(5)

        #expect(count.get() == 5)
        #expect(count.sets.isEmpty)
    }
}
