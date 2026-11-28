//
//  StaticDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How a generated double's static members behave once the compiler builds it.
@Suite("Generated doubles of static members")
struct StaticDoubleTests {
    @Test("Static spies answer what the test scripts and record calls and sets")
    func staticSpyAnswersWhatTheTestScripts() async throws {
        try await SpyStopwatch.withFreshSpies {
            try await CalendarSpy.withFreshSpies {
                SpyStopwatch.elapsedSpy.willReturn(5)
                CalendarSpy.todaySpy.willReturn("Monday")

                let elapsed = SpyStopwatch.elapsed()
                SpyStopwatch.unit = "ms"
                let today = CalendarSpy.today()
                let zone = CalendarSpy.zone

                let expectedUnits = ["ms"]
                #expect(elapsed == 5)
                #expect(SpyStopwatch.elapsedSpy.callCount == 1)
                #expect(SpyStopwatch.unitSpy.sets == expectedUnits)
                #expect(today == "Monday")
                #expect(zone == "")
            }
        }
    }

    @Test("A main actor double's static spies build and answer")
    func mainActorDoubleStaticSpies() async throws {
        try await SpyMainClock.withFreshSpies {
            SpyMainClock.nowSpy.willReturn(9)

            let now = await SpyMainClock.now()

            #expect(now == 9)
            #expect(SpyMainClock.nowSpy.callCount == 1)
        }
    }
}

/// Measures time for the whole app, through static members.
private protocol Stopwatch {
    static var unit: String { get set }
    static func elapsed() -> Int
    func lap()
}

/// A stopwatch whose static answers the test scripts.
///
/// Conformances:
/// - `Stopwatch`, so a test can pass its type where a stopwatch is expected.
@GenerateSpies
private final class SpyStopwatch: Stopwatch {
    @SpiedProperty static var unit: String = "s"
    @Spied static func elapsed() -> Int
    @Spied func lap()
}

/// Tells the day and the time zone, through static members.
@GenerateSpies
private protocol Calendar {
    static var zone: String { get set }
    static func today() -> String
}

/// A clock read on the main actor, through a static member.
@MainActor
@GenerateSpies
private final class SpyMainClock {
    @Spied static func now() -> Int?
}
