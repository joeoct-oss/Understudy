//
//  WaitingBenchmarks.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// What a test pays to wait for a call, and to hold one and resume it.
@Suite("Waiting", .serialized)
struct WaitingBenchmarks {
    /// The round trips each run makes.
    private static let trips = 1_000

    @Test("Waiting for a call another task makes")
    func waitingForACall() async {
        await Measure.time("Waiting", "`nextCall(within:)` for another task's call", count: Self.trips, unit: "µs") {
            let spy = Spy<Int, Void>()
            for trip in 0..<Self.trips {
                let caller = Task {
                    spy(trip)
                }
                _ = await spy.nextCall(within: 1)
                await caller.value
            }
        }
    }

    @Test("Holding a call and resuming it")
    func holdingACall() async {
        await Measure.time("Waiting", "`holdNextCall()`, `arrived()`, `resume`", count: Self.trips, unit: "µs") {
            let spy = Spy<Int, Int>(returning: 0)
            for trip in 0..<Self.trips {
                let held = spy.holdNextCall()
                async let answer = spy.respond(to: trip)
                _ = await held.arrived()
                held.resume(returning: trip)
                _ = await answer
            }
        }
    }
}
