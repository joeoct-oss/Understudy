# Changelog

All notable changes to this package are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `@Understudy`, a macro that writes a test double. On a class in a test target, it writes a spy and a body for every requirement marked `@Spied` and declared with no body, and an initializer that asks for every answer with no safe default. On a protocol, it writes a spy class next to it, named after the protocol with `Spy` added.
- `@Spied`, which marks the requirements `@Understudy` writes.

## 0.1.0 - 2026-11-25

### Added

- `Spy`, which keeps every input a test double's requirement is called with and answers as the test scripts: a standing answer, one-off answers queued in front of it (`willReturnNext(_:then:)`, `willGiveNext(_:then:)`), or an answer worked out from the input.
- `ThrowingSpy`, the same for requirements that throw, with errors scripted like answers.
- Both are safe under Swift 6 strict concurrency: `Sendable` when their input and output are, and usable from main-actor doubles that take values which aren't `Sendable`.
