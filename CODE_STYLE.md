# Code style

This package follows Waypoint's [CODE_STYLE.md](https://github.com/joeoct-oss/Waypoint/blob/main/CODE_STYLE.md), the one home for the code style of Yousef's Swift packages: code, docs and examples. The rules aren't restated here.

Rules of this package's own:

## Foundation only

The library imports Foundation and nothing else, and has no dependencies, so it builds on Linux and every Apple platform and costs a test target almost nothing to add. No macros and no swift-syntax.

## Every isolation is written, and the spies carry none

A spy has no actor, so main-actor doubles and `Sendable` doubles can both hold one. Shared state is read and written under a lock. A type is `Sendable` only when every value it stores is, and says so in its conformance comment.

## Supports the platforms in Package.swift

No API newer than the oldest platform in `Package.swift` (iOS 13, macOS 10.15), unless it is behind an availability check. For example, `NSLock.withLock` needs iOS 17, so the lock is taken by hand.
