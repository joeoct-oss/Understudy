//
//  DoubleAProtocolWithAnInitGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

#if compiler(>=6.1)
import Testing
import Understudy

@GenerateSpies
private protocol Session {
    init(user: String) throws

    func ping() -> Int
}

private func start<Made: Session>(_ type: Made.Type) throws -> Made {
    try Made(user: "ana")
}

/// Why a session can't start.
///
/// Conformances:
/// - `Error`, so the init's spy can throw it.
/// - `Equatable`, so the test can check which error came out.
private enum SessionError: Error, Equatable {
    case locked
}

/// What draws a page with a title.
private protocol Renderer {
    init(title: String)

    func draw()
}

/// The class form of a double for `Renderer`: it writes the `init` and records it.
///
/// Conformances:
/// - `Renderer`, so production code can make it through the protocol's `init`.
@GenerateSpies
private final class SpyRenderer: Renderer {
    convenience init(title: String) {
        self.init()
        Self.made(title: title)
    }

    @Spied static func made(title: String)
    @Spied func draw()
}

/// The examples of the "Double a protocol that declares an initializer" guide, as it shows them.
@Suite("Guide: double a protocol that declares an initializer")
struct DoubleAProtocolWithAnInitGuide {
    @Test("A protocol's init records each call, one that throws included, and throws what the test scripted")
    func protocolInitRecordsAndThrows() async throws {
        try await SessionSpy.withFreshSpies {
            _ = try start(SessionSpy.self)

            let expectedUsers = ["ana"]
            #expect(SessionSpy.initSpy.calls == expectedUsers)

            SessionSpy.initSpy.willThrow(SessionError.locked)
            #expect(throws: SessionError.locked) { try start(SessionSpy.self) }

            #expect(SessionSpy.initSpy.callCount == 2)
        }
    }

    @Test("A class double's init records its call through a static spy, and the double still records its own calls")
    func classInitRecordsThroughAStaticSpy() async throws {
        try await SpyRenderer.withFreshSpies {
            let renderer = SpyRenderer(title: "Menu")
            renderer.draw()

            let expectedTitles = ["Menu"]
            #expect(SpyRenderer.madeSpy.calls == expectedTitles)
            #expect(renderer.drawSpy.callCount == 1)
        }
    }
}
#endif
