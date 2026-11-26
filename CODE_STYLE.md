# Code style

This package follows Waypoint's [CODE_STYLE.md](https://github.com/joeoct-oss/Waypoint/blob/main/CODE_STYLE.md), the one home for the code style of Yousef's Swift packages: code, docs and examples. The rules aren't restated here.

Rules of this package's own:

## Where code goes

Each file holds one job, named after it, in the folder for its part of the package:

| Folder | Holds |
| --- | --- |
| `Sources/Understudy/Spies/` | `Spy`, `ThrowingSpy`, `PropertySpy`, `@Recorded` and the ledger they write to |
| `Sources/Understudy/Waiting/` | Held calls and their delivery |
| `Sources/Understudy/Checking/` | Call order and verification |
| `Sources/Understudy/Traits/` | `.freshSpies` and `.verifiesMocks` |
| `Sources/Understudy/Clock/` | `TestClock` |
| `Sources/UnderstudyMacros/Macros/` | The macros themselves and the compiler plugin |
| `Sources/UnderstudyMacros/Requirements/` | Reading a requirement: functions, properties, subscripts and the types they record |
| `Sources/UnderstudyMacros/Protocols/` | The spy written next to a protocol |
| `Sources/UnderstudyMacros/Writing/` | The code the macros write: storage, forwarding and generated names |
| `Sources/UnderstudyMacros/Diagnostics/` | Errors and fix-its |
| `Tests/*/` | One file per feature, with shared doubles and tables under `Fixtures/` |

A file in `Sources/` has at most 250 lines of code, one in `Tests/` at most 400, and a body in `Sources/` at most 40 lines; blank lines and comments don't count toward a file. Comments fit in 100 columns and code in 120. [`scripts/check-structure.py`](scripts/check-structure.py), the one home for these limits, checks them on every pull request. A file or a body that grows past them is split by job, not squeezed.

## Swift only

Everything is Swift: the runtime imports Foundation and nothing else, and the macros are built on swift-syntax, the package's one dependency, so it builds on Linux and every Apple platform. No Objective-C runtime tricks.

## Macros write what a person would

The code a macro writes reads like a double written by hand: a stored spy per requirement and a body that calls it. Every requirement a macro can't write gets an error that says what to do instead. How the macros are tested is under [Tests prove behaviour](#tests-prove-behaviour-and-every-line-is-tested).

## Every isolation is written, and the spies carry none

A spy has no actor, so main-actor doubles and `Sendable` doubles can both hold one. Shared state is read and written under a lock. A type is `Sendable` only when every value it stores is, and says so in its conformance comment.

## Supports the platforms in Package.swift

No API newer than the oldest platform in `Package.swift` (iOS 13, macOS 10.15), unless it is behind an availability check. For example, `NSLock.withLock` needs iOS 17, so the lock is taken by hand.

## Tests prove behaviour, and every line is tested

Tests check what a person using the package sees: what a spy keeps and answers, how a generated double behaves once the compiler builds it, and which code the macros accept or refuse, with the message and the place it points to. No test compares the text a macro writes, since that is how it works, not what it promises. A macro test expands source in process and checks only what a person sees: the diagnostics (message, place and fix-its), and the parts of an expansion that a running test can't show, such as a stop message, the generated initializer's parameters, the access level or a member that must not exist. One promise has one test; a test that repeats another's promise is merged into it. Every test states its promise as a display name, as Waypoint's [Every test names the promise it pins](https://github.com/joeoct-oss/Waypoint/blob/main/CODE_STYLE.md#every-test-names-the-promise-it-pins) says.

Everything runs on Linux, in the cloud and in CI, with no Mac. The [Linux checks](.github/workflows/ci.yml) workflow runs the tests on the lowest Swift version (6.0, with the lowest swift-syntax `Package.swift` allows) and the newest (6.4) on every pull request, and on every version from 6.0 on main before a release is published. `scripts/check-coverage.sh` runs the tests with coverage and fails on any line of `Sources/` that no test runs, except the compiler plugin's entry point.
