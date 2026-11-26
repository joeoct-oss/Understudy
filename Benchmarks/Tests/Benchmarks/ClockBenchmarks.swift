//
//  ClockBenchmarks.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// What moving a `TestClock` costs for the sleeps it wakes: tasks that end once woken, tasks that
/// sleep again, and work that hops across actors between sleeps. Each benchmark moves the clock
/// with `run()` last, which also wakes a task that reached its sleep late, so none can hang.
@Suite("Test clock", .serialized)
struct ClockBenchmarks {
    /// The numbers of sleeping tasks each advance wakes.
    private static let sleepers = [1, 10, 100]

    /// Times `run()` over `count` tasks that each sleep once and end when woken.
    @Test("Running the clock past sleeps whose tasks end once woken", arguments: sleepers)
    func wakingTasksThatEnd(_ count: Int) async throws {
        try await Measure.time("Test clock", "`run` waking tasks that then end, ×\(count)", count: 1, unit: "ms") {
            let clock = TestClock()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        try await clock.sleep(for: .seconds(1))
                    }
                }
                await clock.run()
                try await group.waitForAll()
            }
        }
    }

    /// Times `advance(by:)` to the first sleeps, then `run()` through the second, over `count`
    /// tasks that each sleep twice.
    @Test("Advancing past sleeps whose tasks sleep again, then running the clock out", arguments: sleepers)
    func wakingTasksThatSleepAgain(_ count: Int) async throws {
        let name = "`advance`, then `run`, over tasks that sleep twice, ×\(count)"
        try await Measure.time("Test clock", name, count: 1, unit: "ms") {
            let clock = TestClock()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        try await clock.sleep(for: .seconds(1))
                        try await clock.sleep(for: .seconds(1))
                    }
                }
                await clock.advance(by: .seconds(1))
                await clock.run()
                try await group.waitForAll()
            }
        }
    }

    /// Times `run()` over a task that sleeps three times and hops to an actor and to the main
    /// actor after each, as the clock's actor-hop test does.
    @Test("Running the clock past work that hops across actors between sleeps")
    func wakingWorkThatHops() async throws {
        try await Measure.time("Test clock", "`run` past 3 sleeps with actor hops between", count: 1, unit: "ms") {
            let clock = TestClock()
            async let hopped: Void = napAndHop(on: clock, times: 3)
            await clock.run()
            try await hopped
        }
    }

    /// Sleeps one second `times` times, hopping to an actor and to the main actor after each.
    private func napAndHop(on clock: TestClock, times: Int) async throws {
        let counter = Counter()
        for _ in 0..<times {
            try await clock.sleep(for: .seconds(1))
            await counter.add()
            await MainActor.run {
                _ = counter
            }
        }
    }
}

/// An actor for woken work to hop to.
private actor Counter {
    /// How many hops so far. `var` because each hop adds one.
    private var hops = 0

    /// Adds one hop.
    func add() {
        hops += 1
    }
}
