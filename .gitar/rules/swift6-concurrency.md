---
title: "Swift 6 concurrency stays checked"
description: "No escape hatch from strict concurrency without a written reason"
type: check
when: "PRs that change Swift files under Sources/, or the code a macro generates"
actions: "Mark the check unmet and name each declaration that breaks it"
---

# Swift 6 concurrency stays checked

The package builds in the Swift 6 language mode with strict concurrency, from Swift 6.0 to the
newest release. `CODE_STYLE.md` ("Every isolation is written, and the spies carry none") is the
home of this rule.

The check is met when the changed code keeps all of these:

- `@unchecked Sendable` and `nonisolated(unsafe)` appear only with a comment above the type or
  value that names the lock guarding every mutable stored value, the way `CallOrder` and
  `HeldCall` do. Each new mutable stored value in such a type is read and written under that lock.
- A checked `Sendable` conformance holds only `Sendable` values, and its conformance comment
  says so. An `@unchecked Sendable` type may hold other values only under the lock above.
- No `@preconcurrency` on a conformance or import, no mutable global or `static var`, and no
  `MainActor.assumeIsolated` or `unsafeBitCast` to get around an isolation error.
- Spies and the code the macros generate carry no actor: no `@MainActor` or other global actor
  on a spy, so main-actor and `Sendable` doubles can both hold one. A generated member's
  isolation follows the requirement it implements.
- No unstructured `Task` where `async let` or a task group would do, no semaphore or other
  blocking wait on async work, and no `Task` in `deinit` that captures `self`.
- No Swift 6.1 or later syntax or library API (such as `@concurrent`,
  `nonisolated(nonsending)`, `InlineArray`, `Span`) unless it is behind `#if compiler(>=6.x)`.

Raise a data race only with a realistic sequence of calls that triggers it. Don't count: missing
`Sendable` on an actor, a `sending` parameter, `nonisolated` on a member that reads only `let`
state, or a lock taken by hand instead of `NSLock.withLock` (that needs iOS 17).
