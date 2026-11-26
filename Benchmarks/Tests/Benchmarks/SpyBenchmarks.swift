//
//  SpyBenchmarks.swift
//  UnderstudyBenchmarks
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// What a call on each kind of spy costs, what reading a long record costs, and what taking
/// queued answers costs. One after another, so no benchmark slows another.
@Suite("Spies", .serialized)
struct SpyBenchmarks {
    /// The calls each run makes.
    private static let calls = 100_000

    /// The calls a spy holds before its record is read.
    private static let recorded = 10_000

    /// The reads each run makes of that record.
    private static let reads = 1_000

    /// The tasks that call one spy at once.
    private static let tasks = 8

    @Test("A call on Spy")
    func spyCall() async {
        await Measure.time("Spies", "A call on `Spy`", count: Self.calls, unit: "ns") {
            let spy = Spy<Int, Int>(returning: 0)
            for call in 0..<Self.calls {
                _ = spy(call)
            }
        }
    }

    @Test("A call on ThrowingSpy")
    func throwingSpyCall() async throws {
        try await Measure.time("Spies", "A call on `ThrowingSpy`", count: Self.calls, unit: "ns") {
            let spy = ThrowingSpy<Int, Int>(returning: 0)
            for call in 0..<Self.calls {
                _ = try spy(call)
            }
        }
    }

    @Test("A get and a set on PropertySpy")
    func propertySpyGetAndSet() async {
        await Measure.time("Spies", "A get and a set on `PropertySpy`", count: Self.calls, unit: "ns") {
            let spy = PropertySpy<Int>(returning: 0)
            for call in 0..<Self.calls {
                spy.set(spy.get() + call)
            }
        }
    }

    @Test("A call on Spy from 8 tasks at once")
    func spyCallFromManyTasks() async {
        await Measure.time("Spies", "A call on `Spy`, from 8 tasks at once", count: Self.calls, unit: "ns") {
            let spy = Spy<Int, Int>(returning: 0)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.tasks {
                    group.addTask {
                        for call in 0..<(Self.calls / Self.tasks) {
                            _ = spy(call)
                        }
                    }
                }
            }
        }
    }

    @Test("Reading calls, callCount and verify() on a spy with 10,000 calls")
    func readingALongRecord() async {
        let spy = Spy<Int, Int>(returning: 0)
        for call in 0..<Self.recorded {
            _ = spy(call)
        }
        await Measure.time("Spies", "`calls` on a spy with 10,000 calls", count: Self.reads, unit: "µs") {
            for _ in 0..<Self.reads {
                _ = spy.calls.count
            }
        }
        await Measure.time("Spies", "`callCount` on a spy with 10,000 calls", count: Self.reads, unit: "µs") {
            for _ in 0..<Self.reads {
                _ = spy.callCount
            }
        }
        await Measure.time("Spies", "`verify()` on a spy with 10,000 calls", count: Self.reads, unit: "µs") {
            for _ in 0..<Self.reads {
                _ = spy.verify()
            }
        }
    }

    // Ten answers, not the 1,000 the plan first named: `willReturnNext` takes its answers one by
    // one, so a test writes each out, and ten is already more than most tests queue.
    @Test("Taking ten queued answers one by one")
    func takingQueuedAnswers() async {
        let spy = Spy<Int, Int>(returning: 0)
        await Measure.time("Spies", "Queuing ten answers and taking each with a call", count: 10_000, unit: "ns") {
            for _ in 0..<1_000 {
                spy.willReturnNext(
                    0,
                    then: 1,
                    2,
                    3,
                    4,
                    5,
                    6,
                    7,
                    8,
                    9
                )
                for call in 0..<10 {
                    _ = spy(call)
                }
            }
        }
    }
}
