//
//  AsyncDoubleTests.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// How a generated double of an async or throwing function behaves once the compiler builds it.
@Suite("Generated doubles of async and throwing functions")
struct AsyncDoubleTests {
    // The error the tests script.
    //
    // Conformances:
    // - `Error`, so a generated spy can throw it.
    // - `Equatable`, so a test can check which error came out.
    private enum LoadError: Error, Equatable {
        case offline
    }

    @Test("An async throwing requirement throws the scripted error and records the call")
    func throwingAndAsyncRequirementsUseAThrowingSpy() async {
        let loader = SpyLoader(load: "data")
        loader.loadSpy.willThrow(LoadError.offline)

        await #expect(throws: LoadError.offline) {
            try await loader.load(path: "a")
        }
        let expectedPaths = ["a"]
        #expect(loader.loadSpy.calls == expectedPaths)
    }

    @Test("A typed throws requirement throws the scripted error")
    func typedThrowsRequirementThrowsTheScriptedError() async {
        let auth = SpyAuth(signIn: "ana")
        let protocolAuth = AuthSpy(signIn: "ana")
        auth.signInSpy.willThrow(AuthError.wrongPassword)
        protocolAuth.signInSpy.willThrow(AuthError.wrongPassword)

        await #expect(throws: AuthError.wrongPassword) {
            try await auth.signIn(email: "ana@example.com")
        }
        await #expect(throws: AuthError.wrongPassword) {
            try await protocolAuth.signIn(email: "ana@example.com")
        }
    }

    @Test("A typed throws requirement returns the scripted answer and records the call")
    func typedThrowsRequirementReturnsTheScriptedAnswer() async throws {
        let auth = SpyAuth(signIn: "ana")
        let protocolAuth = AuthSpy(signIn: "bo")

        let account = try await auth.signIn(email: "ana@example.com")
        let protocolAccount = try await protocolAuth.signIn(email: "bo@example.com")
        auth.forget()
        try auth.refresh()

        let expectedEmails = ["ana@example.com"]
        #expect(account == "ana")
        #expect(protocolAccount == "bo")
        #expect(auth.signInSpy.calls == expectedEmails)
        #expect(auth.forgetSpy.callCount == 1)
        #expect(auth.refreshSpy.callCount == 1)
    }

    @Test("An async requirement can be held until the test resumes it")
    func asyncRequirementCanBeHeldUntilTheTestResumesIt() async throws {
        let loader = SpyLoader(load: "scripted")
        let clock = WallClockSpy(now: 0)
        let load = loader.loadSpy.holdNextCall()
        let sleep = clock.sleepSpy.holdNextCall()

        let loading = Task {
            try await loader.load(path: "a")
        }
        let sleeping = Task {
            await clock.sleep(for: 3)
        }
        let path = await load.arrived()
        let seconds = await sleep.arrived()
        load.resume(returning: "held")
        sleep.resume(returning: ())
        let data = try await loading.value
        await sleeping.value

        #expect(path == "a")
        #expect(seconds == 3)
        #expect(data == "held")
    }
}

/// Loads data that may not be there.
private protocol Loader {
    func load(path: String) async throws -> String
}

/// A loader whose answers the test scripts.
///
/// Conformances:
/// - `Loader`, so a test can pass it where a loader is expected.
@GenerateSpies
private final class SpyLoader: Loader {
    @Spied func load(path: String) async throws -> String
}

/// Why signing in failed.
///
/// Conformances:
/// - `Error`, so a sign-in can throw it.
/// - `Equatable`, so a test can check which error came out.
private enum AuthError: Error, Equatable {
    case wrongPassword
}

/// Signs a person in and out, throwing only `AuthError`.
@GenerateSpies
private protocol Auth {
    func signIn(email: String) async throws(AuthError) -> String
}

/// Signs a person in and out, with every way to write `throws`.
private protocol AuthService {
    func signIn(email: String) async throws(AuthError) -> String
    func refresh() throws(any Error)
    func forget() throws(Never)
}

/// An auth service whose answers and errors the test scripts.
///
/// Conformances:
/// - `AuthService`, so a test can pass it where an auth service is expected.
@GenerateSpies
private final class SpyAuth: AuthService {
    @Spied func signIn(email: String) async throws(AuthError) -> String
    @Spied func refresh() throws(any Error)
    @Spied func forget() throws(Never)
}
