//
//  CheckThatAMockWasUsedGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

/// The examples of the "Check that a mock was used" guide, as the guide shows them.
@Suite("Guide: check that a mock was used")
struct CheckThatAMockWasUsedGuide {
    private let analytics = AnalyticsSpy()
    private let checkout: TrackedCheckout
    private let payment: TrackedPayment

    init() {
        checkout = TrackedCheckout(analytics: analytics)
        payment = TrackedPayment(analytics: analytics)
    }

    @Test("Completing a checkout tracks it, and the two views before it")
    func checkoutTracksItsEvents() {
        analytics.trackSpy.expect("checkout")
        analytics.trackSpy.expect(times: 2) { $0.hasPrefix("view") }

        checkout.complete()

        analytics.trackSpy.verify()
    }

    @Test(.verifiesMocks)
    func payingSendsOnePaymentEvent() {
        analytics.trackSpy.expect("paid")

        payment.confirm()
    }
}

/// Where the app sends the events it tracks.
///
/// Requirements:
/// - `Sendable`, so the suite can keep its spy.
@GenerateSpies
private protocol Analytics: Sendable {
    func track(_ event: String)
}

/// A checkout that tracks the cart and receipt views, then the checkout itself.
private struct TrackedCheckout {
    let analytics: any Analytics

    func complete() {
        analytics.track("view cart")
        analytics.track("view receipt")
        analytics.track("checkout")
    }
}

/// A payment that tracks one event when it is confirmed.
private struct TrackedPayment {
    let analytics: any Analytics

    func confirm() {
        analytics.track("paid")
    }
}
#endif
