//
//  GiveEachTestItsOwnStaticSpiesGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

/// What tells the time of day, by the sun.
protocol Sundial {
    static func hour() -> Int?
}

/// The sundial the greeting tests read.
///
/// Conformances:
/// - `Sundial`, so the greeting can read it in place of the real sundial.
@GenerateSpies
final class SpySundial: Sundial {
    @Spied static func hour() -> Int?
}

@Suite("Greetings", .freshSpies(SpySundial.self))
struct GreetingTests {
    @Test("Greets the morning")
    func greetsTheMorning() {
        SpySundial.hourSpy.willReturn(8)

        #expect(greeting(by: SpySundial.self) == "Good morning")
    }
}

/// The example of the guide's protocol form, as the guide shows it.
@Suite("Guide: give each test its own static spies")
struct GiveEachTestItsOwnStaticSpiesGuide {
    @Test("Each body a protocol's spy runs gets its own static spies")
    func protocolSpyRunsEachBodyWithItsOwnSpies() async throws {
        try await MetronomeSpy.withFreshSpies {
            MetronomeSpy.beatSpy.willReturn(3)

            #expect(MetronomeSpy.beat() == 3)
        }
        try await MetronomeSpy.withFreshSpies {
            #expect(MetronomeSpy.beat() == 0)
            #expect(MetronomeSpy.beatSpy.callCount == 1)
        }
    }
}

/// What counts the beat of a song.
@GenerateSpies
private protocol Metronome {
    static func beat() -> Int
}

/// The greeting for the hour the sundial tells, or a plain one when it tells none.
private func greeting(by sundial: any Sundial.Type) -> String {
    guard let hour = sundial.hour() else {
        return "Hello"
    }
    return hour < 12 ? "Good morning" : "Good afternoon"
}
#endif
