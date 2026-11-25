# Changelog

All notable changes to this package are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `CallOrder { ... }`, which watches every spy in a block of `Watch(spy, as: name)` lines, for `Spy` and `ThrowingSpy` alike. `watch(_:as:)` stays, for a spy the test starts watching later.

### Fixed

- Understudy now asks for swift-syntax 602 or later. It said 600, but the macros don't build with 600, and 601 gives a wrong extra error for a `@SpiedProperty` with accessors, so a project that resolved either got a broken Understudy.

## 0.4.0 - 2026-11-25

### Changed

- `@Understudy` is now `@GenerateSpies`, which says what it does: it writes a spy for every `@Spied` function and `@SpiedProperty` property. `@Spied` and `@SpiedProperty` keep their names. Replace `@Understudy` with `@GenerateSpies`; nothing else changes.
- The README is a short guide: requirements, install, a quick start, one small example per feature, and what the macros refuse and why. Every example is checked against the current API.

### Added

- `reset()` on `Spy`, `ThrowingSpy` and `PropertySpy`, which forgets the calls (or gets and sets), where `nextCall(within:)` was, and the expectations, and keeps the scripted answers.
- Actor doubles: `@GenerateSpies` on an `actor` writes the same members as on a class, with `nonisolated` spies a test reads without `await`. On a protocol that inherits `Actor`, it writes an actor spy.
- Generic functions: `@Spied` writes a generic function whose generic parameters are whole parameter types or the whole return type (`T` or `T?`). The spy records each as `any` of its constraints, or `Any`, and the answer is cast back to the type the caller asks for.

## 0.3.0 - 2026-11-25

### Added

- `@SpiedProperty`, which marks a `var` of an `@Understudy` class for the macro to write, and `PropertySpy`, which keeps every value set, counts the gets and answers with the last value set. `@Understudy` on a protocol now writes its `var` requirements too.
- Held calls: `holdNextCall()` makes the next async call wait until the test resumes it with an answer, an error or the scripted answer. Async requirements written by `@Understudy` go through the new `respond(to:)`, so they can be held.
- `nextCall(within:)`, which waits for a call made from another task, giving each call once, in order.
- `CallOrder`, which keeps the order of calls across several spies.
- Strict spies: `expect(_:times:)`, `expect(times:where:)` and `expectNoCalls()`, checked by `verify()`, which records each expected call that didn't happen and each call nobody expected as a Swift Testing issue.

## 0.2.0 - 2026-11-25

### Added

- `@Understudy`, a macro that writes a test double. On a class in a test target, it writes a spy and a body for every requirement marked `@Spied` and declared with no body, and an initializer that asks for every answer with no safe default. On a protocol, it writes a spy class next to it, named after the protocol with `Spy` added.
- `@Spied`, which marks the requirements `@Understudy` writes.

## 0.1.0 - 2026-11-25

### Added

- `Spy`, which keeps every input a test double's requirement is called with and answers as the test scripts: a standing answer, one-off answers queued in front of it (`willReturnNext(_:then:)`, `willGiveNext(_:then:)`), or an answer worked out from the input.
- `ThrowingSpy`, the same for requirements that throw, with errors scripted like answers.
- Both are safe under Swift 6 strict concurrency: `Sendable` when their input and output are, and usable from main-actor doubles that take values which aren't `Sendable`.
