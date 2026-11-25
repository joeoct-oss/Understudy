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
}
