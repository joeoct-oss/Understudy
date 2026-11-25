# Code style

This package follows Waypoint's [CODE_STYLE.md](https://github.com/joeoct-oss/Waypoint/blob/main/CODE_STYLE.md), the one home for the code style of Yousef's Swift packages: code, docs and examples. The rules aren't restated here.

Rules of this package's own:

## Swift only

Everything is Swift: the runtime imports Foundation and nothing else, and the macros are built on swift-syntax, the package's one dependency, so it builds on Linux and every Apple platform. No Objective-C runtime tricks.

## Macros write what a person would

The code a macro writes reads like a double written by hand: a stored spy per requirement and a body that calls it. Every expansion has a test that shows the code it writes, and every requirement a macro can't write gets an error that says what to do instead.

## Every isolation is written, and the spies carry none

A spy has no actor, so main-actor doubles and `Sendable` doubles can both hold one. Shared state is read and written under a lock. A type is `Sendable` only when every value it stores is, and says so in its conformance comment.

## Supports the platforms in Package.swift

No API newer than the oldest platform in `Package.swift` (iOS 13, macOS 10.15), unless it is behind an availability check. For example, `NSLock.withLock` needs iOS 17, so the lock is taken by hand.

## Tests prove behaviour, and every line is tested

Tests check what a person using the package sees: what a spy keeps and answers, how a generated double behaves once the compiler builds it, and which code the macros accept or refuse, with the message and the place it points to. No test compares the text a macro writes, since that is how it works, not what it promises. One promise has one test; a test that repeats another's promise is merged into it.

Everything runs on Linux, in the cloud and in CI, with no Mac. `scripts/check-coverage.sh` runs the tests with coverage and fails on any line of `Sources/` that no test runs, except the compiler plugin's entry point.
