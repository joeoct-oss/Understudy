# Changelog

All notable changes to this package are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.0 - 2026-11-25

### Added

- `Spy`, which keeps every input a test double's requirement is called with and answers as the test scripts: a standing answer, one-off answers queued in front of it (`willReturnNext(_:then:)`, `willGiveNext(_:then:)`), or an answer worked out from the input.
- `ThrowingSpy`, the same for requirements that throw, with errors scripted like answers.
- Both are safe under Swift 6 strict concurrency: `Sendable` when their input and output are, and usable from main-actor doubles that take values which aren't `Sendable`.
