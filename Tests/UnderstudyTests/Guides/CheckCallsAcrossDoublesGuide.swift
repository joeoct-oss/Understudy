//
//  CheckCallsAcrossDoublesGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// The example of the "Check calls across doubles" guide, as the guide shows it.
@Suite("Guide: check calls across doubles")
struct CheckCallsAcrossDoublesGuide {
    @Test("Completing a checkout saves before it sends")
    func checkoutSavesBeforeItSends() {
        let store = CartStoreSpy()
        let sync = CartSyncSpy()
        let checkout = OrderingCheckout(store: store, sync: sync)

        let order = CallOrder {
            Watched(store.saveSpy, as: "save")
            Watched(sync.sendSpy, as: "send")
        }

        checkout.complete()

        let expectedOrder = ["save", "send"]
        #expect(order.names == expectedOrder)
    }
}

/// Where a checkout keeps the cart.
@GenerateSpies
private protocol CartStore {
    func save()
}

/// What sends the saved cart to the server.
@GenerateSpies
private protocol CartSync {
    func send()
}

/// A checkout that saves the cart, then sends it.
private struct OrderingCheckout {
    let store: any CartStore
    let sync: any CartSync

    func complete() {
        store.save()
        sync.send()
    }
}
