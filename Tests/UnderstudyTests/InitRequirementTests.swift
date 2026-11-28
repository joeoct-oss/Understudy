//
//  InitRequirementTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How the spy written next to a protocol that declares an `init` builds and records. A trait can't
/// name a spy class written next to a protocol, so each test asks the spy for fresh static spies
/// itself, as `.freshSpies(...)` would.
@Suite("Init requirements")
struct InitRequirementTests {
    @Test("The protocol's init builds the double with its first answers, and records the argument")
    func protocolInitRecordsItsArgument() async throws {
        try await WalletSpy.withFreshSpies {
            let wallet = try makeWallet(WalletSpy.self, user: "ana")

            let expectedUsers = ["ana"]
            #expect(WalletSpy.initSpy.calls == expectedUsers)
            #expect(wallet.balance() == 0)
        }
    }

    @Test("The double's own initializer still takes its answers, and records no init call")
    func ownInitializerIsUnchanged() async throws {
        try await WalletSpy.withFreshSpies {
            let wallet = WalletSpy(balance: 3)

            #expect(wallet.balance() == 3)
            #expect(!WalletSpy.initSpy.wasCalled)
        }
    }

    @Test("Overloaded inits each record on their own spy, several parameters as a labelled tuple")
    func overloadedInitsRecordOnTheirOwnSpies() async throws {
        try await MemberSpy.withFreshSpies {
            _ = MemberSpy()
            _ = MemberSpy(user: "ana")
            _ = MemberSpy(user: "bo", age: 7)

            let expectedUsers = ["ana"]
            #expect(MemberSpy.initSpy.callCount == 1)
            #expect(MemberSpy.initUserSpy.calls == expectedUsers)
            #expect(MemberSpy.initUserAgeSpy.lastCall?.user == "bo")
            #expect(MemberSpy.initUserAgeSpy.lastCall?.age == 7)
        }
    }

    @Test("The protocol's init() is the double's one initializer, so the test's own is recorded too")
    func protocolInitReplacesAnInitializerThatTakesNothing() async throws {
        try await MemberSpy.withFreshSpies {
            let member = MemberSpy()
            let made = makeMember(MemberSpy.self)

            member.refresh()
            made.refresh()

            #expect(MemberSpy.initSpy.callCount == 2)
            #expect(member.refreshSpy.callCount == 1)
        }
    }

    @Test("Beside an own initializer with defaults, init() is the protocol's and init(count:) isn't")
    func protocolInitBesideAnOwnInitializerWithDefaults() async throws {
        try await TallySpy.withFreshSpies {
            let empty = TallySpy()
            let three = TallySpy(count: 3)

            #expect(TallySpy.initSpy.callCount == 1)
            #expect(empty.count() == 0)
            #expect(three.count() == 3)
        }
    }

    @Test("An init whose type differs from the own initializer's answer still reaches it, not itself")
    func initBesideAnAnswerOfAnotherType() async throws {
        try await GaugeSpy.withFreshSpies {
            let gauge = makeGauge(GaugeSpy.self, level: 3)

            let expectedLevels = [3]
            #expect(GaugeSpy.initSpy.calls == expectedLevels)
            #expect(gauge.level() == 0)
        }
    }

    @Test("A variadic init beside an answer of its array type builds, and each reaches its own")
    func variadicInitBesideAnArrayAnswer() async throws {
        try await PlaylistSpy.withFreshSpies {
            let ownTracks = ["demo"]
            let made = makePlaylist(PlaylistSpy.self, "intro", "outro")
            let own = PlaylistSpy(tracks: ownTracks)

            let expectedTracks = [["intro", "outro"]]
            #expect(PlaylistSpy.initSpy.calls == expectedTracks)
            #expect(made.tracks().isEmpty)
            #expect(own.tracks() == ownTracks)
        }
    }

    @Test("A nonisolated init under a global actor is made off that actor and records the call")
    func nonisolatedInitUnderAGlobalActor() async throws {
        try await BadgeSpy.withFreshSpies {
            _ = makeBadge(BadgeSpy.self, label: "new")

            let expectedLabels = ["new"]
            #expect(BadgeSpy.initSpy.calls == expectedLabels)
        }
    }

    @Test("An actor's nonisolated async init builds beside an answer and records the call")
    func actorNonisolatedAsyncInit() async throws {
        try await LogbookSpy.withFreshSpies {
            let logbook = await LogbookSpy(owner: "ana")

            let expectedOwners = ["ana"]
            #expect(LogbookSpy.initSpy.calls == expectedOwners)
            #expect(await logbook.total() == 0)
        }
    }

    @Test("An async init can be held, and resumes with the answer the test gives")
    func asyncInitCanBeHeld() async throws {
        try await ConnectionSpy.withFreshSpies {
            let held = ConnectionSpy.initHostSpy.holdNextCall()
            let task = Task { try await ConnectionSpy(host: "example.com") }

            await held.arrived()
            held.resume(throwing: ConnectionError.refused)

            await #expect(throws: ConnectionError.refused) {
                try await task.value
            }
            let expectedHosts = ["example.com"]
            #expect(ConnectionSpy.initHostSpy.calls == expectedHosts)
        }
    }

    @Test("A typed throws init rethrows the scripted error as its type")
    func typedThrowsInitRethrowsAsItsType() async throws {
        try await ConnectionSpy.withFreshSpies {
            ConnectionSpy.initPortSpy.willThrow(ConnectionError.refused)

            #expect(throws: ConnectionError.refused) {
                try ConnectionSpy(port: 80)
            }
        }
    }

    @Test("Actor and main actor protocols with an init build and record")
    func actorAndMainActorProtocolsRecord() async throws {
        try await JournalSpy.withFreshSpies {
            try await BannerSpy.withFreshSpies {
                let journal = JournalSpy(owner: "ana")
                let banner = await BannerSpy(text: "hi")

                let expectedOwners = ["ana"]
                let expectedTexts = ["hi"]
                #expect(JournalSpy.initSpy.calls == expectedOwners)
                #expect(BannerSpy.initSpy.calls == expectedTexts)
                #expect(await journal.total() == 0)
                #expect(await banner.isShown() == false)
            }
        }
    }

    @Test("Parallel tests each see only their own init calls", arguments: 0..<8)
    func parallelTestsSeeOnlyTheirOwnInitCalls(_ user: Int) async throws {
        try await WalletSpy.withFreshSpies {
            _ = try WalletSpy(user: "user \(user)")

            let expectedUsers = ["user \(user)"]
            #expect(WalletSpy.initSpy.calls == expectedUsers)
        }
    }
}

/// Makes a wallet the way production code would, through the protocol.
private func makeWallet<Made: Wallet>(_ type: Made.Type, user: String) throws -> Made {
    try Made(user: user)
}

/// Makes a member the way production code would, through the protocol.
private func makeMember<Made: Member>(_ type: Made.Type) -> Made {
    Made()
}

/// A wallet production code opens for a user.
@GenerateSpies
protocol Wallet {
    init(user: String) throws

    func balance() -> Int
}

/// A member with three ways to make one.
@GenerateSpies
protocol Member {
    init()
    init(user: String)
    init(user: String, age: Int)

    func refresh()
}

/// A tally whose own initializer takes an answer with a default.
@GenerateSpies
protocol Tally {
    init()

    func count() -> Int
}

/// Why a connection failed.
///
/// Conformances:
/// - `Error`, so the typed throws init can name it and its spy can throw it.
enum ConnectionError: Error {
    case refused
}

/// A connection opened with an async init, or with a typed throws one.
///
/// Requirements:
/// - `Sendable`, so the tests check that a `Sendable` spy's inits build and record.
@GenerateSpies
protocol Connection: Sendable {
    init(host: String) async throws
    init(port: Int) throws(ConnectionError)

    func send(_ text: String)
}

/// A journal kept by an actor.
///
/// Requirements:
/// - `Actor`, so the tests check an actor spy's init, which delegates without `convenience`.
@GenerateSpies
protocol Journal: Actor {
    init(owner: String)

    func total() -> Int
}

/// A banner shown on the main actor.
@MainActor
@GenerateSpies
protocol Banner {
    init(text: String)

    func isShown() -> Bool
}

/// Makes a gauge the way production code would, through the protocol.
private func makeGauge<Made: Gauge>(_ type: Made.Type, level: Int) -> Made {
    Made(level: level)
}

/// A gauge made with a whole level, which answers a fractional one: the spy's own initializer
/// takes `level: Double`, and the protocol's `init` takes `level: Int`.
@GenerateSpies
protocol Gauge {
    init(level: Int)

    func level() -> Double
}

/// A playlist made from single tracks, which answers them as an array: the spy's own initializer
/// takes `tracks: [String]`, and the protocol's `init` takes `tracks: String...`.
@GenerateSpies
protocol Playlist {
    init(tracks: String...)

    func tracks() -> [String]
}

/// Makes a playlist the way production code would, through the protocol.
private func makePlaylist<Made: Playlist>(_ type: Made.Type, _ first: String, _ second: String) -> Made {
    Made(tracks: first, second)
}

/// A badge made off the main actor, though it is shown on it. Its spy's own initializer takes no
/// answer, so the protocol's `init` can make it off the actor.
@MainActor
@GenerateSpies
protocol Badge {
    nonisolated init(label: String)

    func show()
}

/// Makes a badge the way production code would, off the main actor, through the protocol.
private func makeBadge<Made: Badge>(_ type: Made.Type, label: String) -> Made {
    Made(label: label)
}

/// A logbook kept by an actor, opened with a `nonisolated` async init beside a requirement whose
/// answer the spy's own initializer takes.
///
/// Requirements:
/// - `Actor`, so the tests check that an actor spy's own initializer stays as an actor needs it.
@GenerateSpies
protocol Logbook: Actor {
    nonisolated init(owner: String) async

    func total() -> Int
}
