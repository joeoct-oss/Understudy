//
//  TestCodeThatWaitsGuide.swift
//  Understudy
//
//  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
//  Copyright © 2026 Yousef Mohamed. MIT License.
//

import Testing
import Understudy

/// The examples of the "Test code that waits" guide, as the guide shows them.
@Suite("Guide: test code that waits")
struct TestCodeThatWaitsGuide {
    @Test("A held refresh shows the screen loading until the test resumes it")
    @MainActor
    func heldRefreshShowsLoading() async {
        let feed = FeedSpy()
        let screen = FeedScreen(feed: feed)

        let refresh = feed.refreshSpy.holdNextCall()
        let task = Task { await screen.reload() }

        await refresh.arrived()
        #expect(screen.isLoading)

        refresh.resume(returning: ())
        await task.value
        #expect(!screen.isLoading)
    }

    @Test("Polling asks the feed for its first page, from a task of its own")
    @MainActor
    func pollingAsksForTheFirstPage() async throws {
        let feed = FeedSpy()
        let screen = FeedScreen(feed: feed)

        screen.startPolling()

        let page = try #require(await feed.pageSpy.nextCall())
        #expect(page == 1)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @Test("Greets after the delay", .timeLimit(.minutes(1)))
    func greetsAfterTheDelay() async throws {
        let clock = TestClock()
        let greeter = Greeter(clock: clock)

        async let greeting = greeter.greet("ana")
        await clock.advance(by: .milliseconds(400))

        #expect(try await greeting == "Hello, ana")
    }
}

/// A feed of pages a screen shows.
///
/// Requirements:
/// - `Sendable`, because the screen calls it from tasks of its own.
@GenerateSpies
private protocol Feed: Sendable {
    func refresh() async
    func page(_ number: Int) async -> [String]
}

/// A screen that shows the feed, and says when it is loading.
@MainActor
private final class FeedScreen {
    // `var` because `reload()` sets it while the feed refreshes.
    private(set) var isLoading = false
    private let feed: any Feed

    init(feed: any Feed) {
        self.feed = feed
    }

    func reload() async {
        isLoading = true
        await feed.refresh()
        isLoading = false
    }

    func startPolling() {
        let feed = feed
        Task {
            _ = await feed.page(1)
        }
    }
}

/// A greeter that waits a moment before it greets.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private final class Greeter: Sendable {
    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func greet(_ name: String) async throws -> String {
        try await clock.sleep(for: .milliseconds(400))
        return "Hello, \(name)"
    }
}
