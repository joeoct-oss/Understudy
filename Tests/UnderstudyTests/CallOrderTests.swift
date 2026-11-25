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
    @Test
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

    @Test
    func callOrderBuilderWatchesEverySpyInIt() throws {
        let save = ThrowingSpy<String, Void>(returning: ())
        let send = Spy<String, Void>()
        let order = CallOrder {
            Watch(save, as: "save")
            Watch(send, as: "send")
        }

        send("hello")
        try save("cart")
        send("saved")

        let expected = ["send", "save", "send"]
        #expect(order.names == expected)
    }

    @Test
    func callOrderBuilderSeesOnlyLaterCalls() {
        let send = Spy<String, Void>()
        send("before watching")

        let order = CallOrder {
            Watch(send, as: "send")
        }
        send("after")

        let expected = ["send"]
        #expect(order.names == expected)
    }

    @Test
    func aBuiltOrderCanWatchMoreSpiesLater() {
        let save = Spy<String, Void>()
        let send = Spy<String, Void>()
        let order = CallOrder {
            Watch(save, as: "save")
        }

        send("not watched yet")
        order.watch(send, as: "send")
        send("watched")
        save("cart")

        let expected = ["send", "save"]
        #expect(order.names == expected)
    }

    @Test
    func aWatchCanBeAppliedToAnOrderByHand() {
        let send = Spy<String, Void>()
        let order = CallOrder()
        let watch = Watch(send, as: "send")

        watch(order)
        send("hello")

        let expected = ["send"]
        #expect(order.names == expected)
    }
}
