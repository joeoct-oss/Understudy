//
//  FreshSpiesTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

/// `.freshSpies(_:)` gives each test its own static spies, so tests that run in parallel never see
/// each other's calls or answers.
@Suite("Fresh static spies", .freshSpies(SpyBeacon.self))
struct FreshSpiesTests {
    @Test(arguments: 0..<8)
    func freshSpiesGivesEachTestItsOwnStaticSpies(_ signal: Int) async {
        SpyBeacon.signalSpy.willReturn(signal)

        async let fromChildTask = SpyBeacon.signal()
        let fromTest = SpyBeacon.signal()

        #expect(await fromChildTask == signal)
        #expect(fromTest == signal)
        #expect(SpyBeacon.signalSpy.callCount == 2)
    }

    /// A trait can't name a spy class written next to a protocol, because Swift doesn't look into
    /// macro expansions from a macro's arguments, so the test asks the double itself.
    @Test(arguments: 0..<8)
    func protocolDoubleGivesFreshSpiesToTheBlockItRuns(_ signal: Int) async throws {
        try await BeaconSpy.withFreshSpies {
            BeaconSpy.signalSpy.willReturn(signal)

            let answer = BeaconSpy.signal()

            #expect(answer == signal)
            #expect(BeaconSpy.signalSpy.callCount == 1)
        }
    }
}

/// Sends a signal for the whole app, through a static member.
@GenerateSpies
protocol Beacon {
    static func signal() -> Int
}

/// A beacon whose static signal each test scripts.
///
/// Conformances:
/// - `Beacon`, so a test can pass its type where a beacon is expected.
@GenerateSpies
final class SpyBeacon: Beacon {
    @Spied static func signal() -> Int
}
#endif
