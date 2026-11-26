//
//  ProtocolFormDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How the spy class written next to a protocol behaves once the compiler builds it.
@Suite("Generated spies next to a protocol")
struct ProtocolFormDoubleTests {
    @Test("A protocol's properties get property spies")
    func protocolPropertiesGetPropertySpies() {
        let settings = SettingsSpy(volume: 3)

        settings.volume = 5
        let theme = settings.theme

        let expectedVolumes = [5]
        #expect(settings.volumeSpy.sets == expectedVolumes)
        #expect(settings.volume == 5)
        #expect(theme == nil)
    }

    @Test("A protocol gets a spy class next to it that records and answers")
    func protocolGetsASpyClassNextToIt() async {
        let clock = WallClockSpy(now: 10)

        let first = clock.now()
        await clock.sleep(for: 2)

        let expectedDurations = [2]
        #expect(first == 10)
        #expect(clock.sleepSpy.calls == expectedDurations)
    }

    @Test("A Sendable protocol's spy keeps every call from concurrent tasks")
    func sendableProtocolGetsASendableSpy() async {
        let sink = EventSinkSpy()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    sink.send("event \(index)")
                }
            }
        }

        #expect(sink.sendSpy.callCount == 100)
    }
}

/// Settings a screen reads and changes.
@GenerateSpies
private protocol Settings: AnyObject {
    var volume: Int { get set }
    var theme: String? { get }
}

/// Receives events from any thread.
///
/// Conformances:
/// - `Sendable`, because any task may send an event.
@GenerateSpies
private protocol EventSink: Sendable {
    func send(_ event: String)
}
