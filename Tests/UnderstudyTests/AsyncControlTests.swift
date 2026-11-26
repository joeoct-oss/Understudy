//
//  AsyncControlTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// A test controls async calls: it holds one until it resumes it, and waits for calls made from
/// other tasks.
@Suite("Holding and waiting for calls")
struct AsyncControlTests {
    /// The error the tests script.
    ///
    /// Conformances:
    /// - `Error`, so a spy can throw it.
    /// - `Equatable`, so a test can check which error came out.
    private enum LoadError: Error, Equatable {
        case offline
    }

    /// How long a test waits for something that must not happen.
    private static let shortWait = 0.05

    @Test("A held call waits until the test resumes it, then returns what the test gave")
    func heldCallWaitsUntilTheTestResumesIt() async {
        let spy = Spy<Int, String>(returning: "scripted")
        let returned = Spy<String, Void>()
        let held = spy.holdNextCall()

        let task = Task {
            returned(await spy.respond(to: 7))
        }
        let input = await held.arrived()
        let returnedWhileHeld = returned.wasCalled
        held.resume(returning: "held")
        await task.value

        let expected = ["held"]
        #expect(input == 7)
        #expect(!returnedWhileHeld)
        #expect(returned.calls == expected)
    }

    @Test("Every task waiting for a held call sees its input")
    func everyTaskWaitingForAHeldCallSeesIt() async {
        let spy = Spy<Int, Void>()
        let held = spy.holdNextCall()

        async let first = held.arrived()
        async let second = held.arrived()
        let task = Task {
            await spy.respond(to: 4)
        }
        let inputs = await [first, second]
        held.resume(returning: ())
        await task.value

        let expected: [Int?] = [4, 4]
        #expect(inputs == expected)
    }

    @Test("A held call can be resumed with the spy's scripted answer")
    func heldCallCanGiveItsScriptedAnswer() async {
        let spy = Spy<Void, String>(returning: "scripted")
        let held = spy.holdNextCall()

        let task = Task {
            await spy.respond(to: ())
        }
        _ = await held.arrived()
        held.resumeWithScriptedAnswer()
        let answer = await task.value

        #expect(answer == "scripted")
    }

    @Test("A call resumed before it arrives returns at once with that answer")
    func callResumedBeforeItArrivesReturnsAtOnce() async {
        let spy = Spy<Int, String>(returning: "scripted")
        let held = spy.holdNextCall()

        held.resume(returning: "early")
        let answer = await spy.respond(to: 1)

        #expect(answer == "early")
    }

    @Test("Only the first resume of a held call counts")
    func onlyTheFirstResumeCounts() async {
        let spy = Spy<Int, String>(returning: "scripted")
        let held = spy.holdNextCall()

        held.resume(returning: "first")
        held.resume(returning: "second")
        let answer = await spy.respond(to: 1)

        #expect(answer == "first")
    }

    @Test("Holding applies to one call, and later calls get the scripted answer")
    func holdingAppliesToOneCallAndOthersAnswerAtOnce() async {
        let spy = Spy<Int, String>(returning: "scripted")
        let held = spy.holdNextCall()
        held.resume(returning: "held")

        let first = await spy.respond(to: 1)
        let second = await spy.respond(to: 2)

        let expected = [1, 2]
        #expect(first == "held")
        #expect(second == "scripted")
        #expect(spy.calls == expected)
    }

    @Test("A held call on a throwing spy can be resumed with an error or an answer")
    func throwingHeldCallCanThrowOrReturn() async throws {
        let loader = ThrowingSpy<String, Int>(returning: 0)
        let failing = loader.holdNextCall()
        let succeeding = loader.holdNextCall()

        failing.resume(throwing: LoadError.offline)
        succeeding.resume(returning: 3)

        await #expect(throws: LoadError.offline) {
            try await loader.respond(to: "a")
        }
        let answer = try await loader.respond(to: "b")
        #expect(answer == 3)
    }

    @Test("Waiting for a held call that never arrives gives nil")
    func heldCallThatNeverArrivesGivesNothing() async {
        let spy = Spy<Int, Void>()
        let held = spy.holdNextCall()

        let input = await held.arrived(within: Self.shortWait)

        #expect(input == nil)
    }

    @Test("nextCall gives the input of a call made from another task")
    func nextCallSeesAnAsyncCallFromAnotherTask() async {
        let spy = Spy<Int, Void>()

        Task {
            await spy.respond(to: 5)
        }
        let input = await spy.nextCall()

        #expect(input == 5)
    }

    @Test("nextCall gives every call once, in order, even calls made before waiting")
    func nextCallGivesEveryCallOnceInOrderEvenIfMadeBeforeWaiting() async {
        let loader = ThrowingSpy<String, Int>(returning: 0)
        _ = try? loader("a")
        _ = try? loader("b")

        let first = await loader.nextCall()
        let second = await loader.nextCall()
        let third = await loader.nextCall(within: Self.shortWait)

        #expect(first == "a")
        #expect(second == "b")
        #expect(third == nil)
    }

    @Test("A call made after a wait ran out goes to the next wait")
    func callAfterAWaitRanOutGoesToTheNextWait() async {
        let spy = Spy<Int, Void>()

        let missed = await spy.nextCall(within: Self.shortWait)
        spy(1)
        let next = await spy.nextCall()

        #expect(missed == nil)
        #expect(next == 1)
    }

    /// The wait and the call race, so the test runs them many times to meet the case where the
    /// wait is on before the call comes.
    @Test("A call that comes while a wait is on is given to that wait only, and a later wait gets the next")
    func callDuringAWaitIsGivenOnce() async {
        for _ in 1...Self.raceRuns {
            let spy = Spy<Int, Void>()

            Task {
                spy(1)
            }
            let first = await spy.nextCall()
            Task {
                spy(2)
            }
            let second = await spy.nextCall()

            #expect(first == 1)
            #expect(second == 2)
        }
    }

    /// The waits and the calls race, so the test runs them many times to meet the case where
    /// both waits are on before the first call comes.
    @Test("Two waits on at once each get a call of their own")
    func twoWaitsAtOnceEachGetTheirOwnCall() async {
        for _ in 1...Self.raceRuns {
            let spy = Spy<Int, Void>()

            async let first = spy.nextCall()
            async let second = spy.nextCall()
            Task {
                spy(1)
                spy(2)
            }
            let inputs: Set = await [first, second]

            #expect(inputs == [1, 2])
        }
    }

    /// How many times a test that races waits against calls runs.
    private static let raceRuns = 200
}
