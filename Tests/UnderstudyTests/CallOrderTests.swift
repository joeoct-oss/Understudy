//
//  CallOrderTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A call order keeps the calls to several spies in the order they were made.
@Suite("Call order")
struct CallOrderTests {
    @Test("CallOrder keeps calls across spies in order, under their names")
    func keepsCallsAcrossSpiesInOrderUnderTheirNames() throws {
        let save = ThrowingSpy<String, Void>(returning: ())
        let send = Spy<String, Void>()
        try save("before watching")
        let order = CallOrder()
        order.watch(save, as: "save")
        order.watch(send, as: "send")

        try save("cart")
        send("saved")
        try save("cart again")

        let expected = ["save", "send", "save"]
        #expect(order.names == expected)
    }

    @Test("Two CallOrders watching the same spy each see its calls")
    func twoCallOrdersWatchingTheSameSpyEachSeeItsCalls() {
        let send = Spy<String, Void>()
        let first = CallOrder()
        let second = CallOrder()
        first.watch(send, as: "send")
        second.watch(send, as: "send")

        send("saved")

        let expected = ["send"]
        #expect(first.names == expected)
        #expect(second.names == expected)
    }

    @Test("A CallOrder block watches every spy listed in it")
    func callOrderBuilderWatchesEverySpyInIt() throws {
        let save = ThrowingSpy<String, Void>(returning: ())
        let send = Spy<String, Void>()
        let order = CallOrder {
            Watched(save, as: "save")
            Watched(send, as: "send")
        }

        send("hello")
        try save("cart")
        send("saved")

        let expected = ["send", "save", "send"]
        #expect(order.names == expected)
    }

    @Test("A CallOrder block sees only calls made after it starts watching")
    func callOrderBuilderSeesOnlyLaterCalls() {
        let send = Spy<String, Void>()
        send("before watching")

        let order = CallOrder {
            Watched(send, as: "send")
        }
        send("after")

        let expected = ["send"]
        #expect(order.names == expected)
    }

    @Test("A CallOrder built from a block can watch more spies later")
    func aBuiltOrderCanWatchMoreSpiesLater() {
        let save = Spy<String, Void>()
        let send = Spy<String, Void>()
        let order = CallOrder {
            Watched(save, as: "save")
        }

        send("not watched yet")
        order.watch(send, as: "send")
        send("watched")
        save("cart")

        let expected = ["send", "save"]
        #expect(order.names == expected)
    }

    @Test("A Watched line can be applied to an order by hand")
    func aWatchCanBeAppliedToAnOrderByHand() {
        let send = Spy<String, Void>()
        let order = CallOrder()
        let watch = Watched(send, as: "send")

        watch(order)
        send("hello")

        let expected = ["send"]
        #expect(order.names == expected)
    }
}
