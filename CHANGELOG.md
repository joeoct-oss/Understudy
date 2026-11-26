# Changelog

All notable changes to this package are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

### Changed

- CI now also checks the package with Apple's toolchain, on GitHub's macOS runners (the **Apple platform checks** workflow): every test on macOS with the newest Xcode and with Xcode 16.0 and the lowest swift-syntax, and the tests built for iOS 13, tvOS 13, watchOS 6 and visionOS 1, so an API newer than a platform's lowest version fails before a release. A release waits for these checks as it does for the Linux checks. Nothing in the package changes.
- CI runs its checks in stages, each starting only when the one before passed: fast checks (workflow lint, size limits, and a review of any changed dependency for known vulnerabilities), then SonarQube Cloud's quality gate, then the Linux checks, then the Apple platform checks, benchmarks and mutation testing. A failure stops the run before the slower checks start. The Apple checks now also run the tests on an iOS simulator, coverage is measured once per run instead of twice, a pull request that changes only docs skips the tests, and the SonarQube scan retries when SonarQube Cloud is rate limited. Nothing in the package changes.

## 1.0.0 - 2026-11-26

The first stable release. Code that compiles against 1.0.0 keeps compiling with every 1.x version: the README's [What 1.x promises](README.md#what-1x-promises) says what each 1.x version keeps and what a minor version may change, and CI now fails any change that would break the public API of the `Understudy` library. The tests were analysed before the release and the code the macros write is now also checked in Swift 5 language mode. Nothing a test writes needs to change.

### Added

- README: [What 1.x promises](README.md#what-1x-promises), what every 1.x version keeps: the public API, the toolchains, swift-syntax and the platforms; and what a minor version may change in the code the macros write.
- `ThrowingSpy()` for a requirement that returns nothing, as `Spy()` already has, so a test needn't write `ThrowingSpy(returning: ())`.
- `scripts/mutate.py`, for contributors: mutation testing. It changes one thing at a time in `Sources/`, such as a comparison, a condition or a statement, runs the tests, and lists each change no test noticed. A Mutation testing workflow runs it on the files a pull request changes and lists what survived in the job summary, without failing.
- The code the macros write is now tested in a Swift 5 language mode project as well: CI builds and runs the package's tests in Swift 5 mode (`Swift5Mode/`), with warnings as errors.
- CI now compares the public API of the Understudy library with the latest released version, and fails a change that would break code using it (the **Public API kept** job). A break meant for a new major version is listed in `.github/api-breakage-allowlist.txt`.
- For maintainers: a Security alerts workflow posts new code scanning and secret scanning alerts to the project's Slack every 2 hours, with only the kind of secret and a link, never the secret (`scripts/post-security-alerts.sh`).

### Changed

- A standard type written with its module, such as `Swift.Int` or `Swift.Set<String>`, now gets its obvious value in the double's initializer, as `Int` and `Set<String>` do, so a test needn't pass it. A static requirement of such a type is no longer refused. Breaking, in the generated code only: `@GenerateSpies` now writes different code for these types. No test needs to change, because an argument only gains a default, so every call that compiled still compiles.
- SonarQube Cloud's quality gate runs first on every pull request and push to main, and checks code quality as well as bugs and security. Until it passes, no other check runs and nothing is released (the **Checks** workflow).
- SonarQube Cloud judges the tests in `Tests/` and `Benchmarks/Tests/` as tests, so they no longer count as source code.
- For contributors: the code-quality issues SonarQube Cloud found in code that was already there are fixed, such as unused parameters, deeply nested closures and two Python functions that were too complex. The macros write the same code.
- For contributors: CodeRabbit reviews every file type in the package with rules of its own, not only Swift: the Python and shell scripts, the workflows and other YAML settings, `sonar-project.properties`, the generated-code budget and the Markdown docs. It posts what Ruff and ShellCheck find inline, and reports security problems in workflows even when CI's workflow lint would also find them.

## 0.9.0 - 2026-11-26

Nothing a test writes changes, and the macros write the same code and give the same messages as in 0.8.0. Spy calls are cheaper, and the package can now measure what it costs a project that uses it.

### Added

- `scripts/benchmark.sh`, for contributors: measures what Understudy costs a project that uses it, and prints one table of medians and ranges. It covers spy calls, waits, the test clock, the traits, how long the macros take to expand, how much code they write and, with `--all` or `--only build`, how long a test target with many doubles takes to build. The runtime benchmarks are in `Benchmarks/`, a package of its own that no project depending on Understudy builds. A Benchmarks workflow shows the table on every pull request, without failing on it. `scripts/compare-expansions.sh` gains `--count` and `--time`.
- `Benchmarks/generated-code-budget.txt`, for contributors: how much code the macros write for the sources under `Tests/`. CI fails when that changes and the budget doesn't, so a pull request that makes the macros write more says so; `scripts/check-generated-code.sh --update` updates it.

### Changed

- A call on `Spy` or `ThrowingSpy` costs about a quarter less in a debug build: a call no longer copies the list of waiting tasks when nothing waits, and takes its lock without a closure.
- For contributors: CodeRabbit's merge risk and security risk ratings now know what is risky in this package, such as the release workflow, the code the macros generate and the macro plugin's limits. The ratings only inform; they never approve or block a merge.

## 0.8.0 - 2026-11-26

Nothing a test writes changes in this release, and the macros write the same code and give the same messages as in 0.7.0. It reorganises the package's own code so it is easier to read and change.

### Added

- `scripts/compare-expansions.sh <git ref>`, for contributors: shows how the code the macros write, and the messages they give, changed since that commit, and prints nothing when they are the same. `--record` prints the whole record. It runs the macros of each commit over every Swift file under `Tests/`, with the tool in `Tools/ExpansionRecord`, a package of its own that no project depending on Understudy builds.

### Changed

- The package's code is in folders by job, one type per file, with functions of a few named steps: the macros in `Macros/`, `Requirements/`, `Protocols/`, `Writing/` and `Diagnostics/`, and the runtime in `Spies/`, `Waiting/`, `Checking/`, `Traits/` and `Clock/`. Every name the generated code uses is written in one place. The tests are in one file per feature. For contributors, `CODE_STYLE.md` says where each kind of code goes, and CI fails when a file, a function body or a line grows past the limits in `scripts/check-structure.py`.

## 0.7.0 - 2026-11-26

### Added

- `TestClock`, a clock that moves only when the test moves it, so code that waits can be tested without real time passing. `advance(by:)` and `advance(to:)` wake each sleep the window reaches, in deadline order, and let the woken code run on to its next sleep, even across actors and the main actor; a woken task reads `now` as the deadline it woke at, so a sleep it starts late still counts from then; `advance()` lets ready work run, and `run()` moves on until nothing waits. A cancelled sleep throws `CancellationError`. It needs macOS 13, iOS 16, tvOS 16 or watchOS 9.
- `@GenerateSpies` on a protocol with associated types writes a generic spy, one generic parameter per associated type with its constraints (`Sendable` added in a `Sendable` protocol and in an actor protocol): `RepositorySpy<Product>()`. A `where` clause on an associated type or on the protocol, and a static requirement next to an associated type, are refused with a message pointing to the class form.
- `@GenerateSpies` on a protocol that inherits another protocol with `@GenerateSpies` writes a spy that stores the parent's spy, taken first by its initializer, `ChildSpy(base: BaseSpy(ping: 3))`, and answers the parent's requirements through it, with the parent's spies read on the child's (`child.pingSpy`). Several parents and a parent's parents work too. For this, the macro also writes `<Name>SpyForwarding` next to every protocol. A parent from the standard library, a parent with associated types, an actor protocol, and a protocol declared inside another type can't be forwarded to, and say so.
- `.verifiesMocks`, a Swift Testing trait for a test or a suite (Swift 6.1 or later): every spy given an expectation during the test is verified when it ends, so a forgotten `verify()` can't pass silently. An unmet expectation is reported at its `expect` line, and a call nobody expected at the test; a spy with no expectations is never checked, and a problem `verify()` already reported isn't reported again. `expect` gains a defaulted `sourceLocation`, so existing calls compile unchanged.
- `.spi.yml`, so the Swift Package Index builds the package and hosts the API docs of `Understudy` and `UnderstudySamples`.
- A coverage report on Codecov for main and each pull request (the **Coverage report** workflow). `scripts/check-coverage.sh` writes the measured lines as one LCOV file when `COVERAGE_LCOV` names a path. The coverage gate itself is unchanged.

### Changed

- Breaking, only for a test that declares its own type named `<Name>SpyForwarding` next to a protocol with `@GenerateSpies`: the macro now writes a protocol of that name there, so the two clash. Rename the test's type.
- Breaking, only for code that keeps a strict spy's `expect` as a function value: `expect(_:times:)` and `expect(times:where:)` gained a `sourceLocation` that defaults to the caller's, so `.verifiesMocks` can point at the `expect` line. Calls don't change. `expect` and `expectNoCalls()` now live, like `verify`, only where Swift Testing can be imported, which every supported toolchain can; without it a strict spy could never report.
- Pull requests run the tests on Swift 6.0 and 6.4 only. Swift 6.1, 6.2 and 6.3 run on every push to main, in the Linux checks a release waits for, so every version still passes before a version is published.
- CodeRabbit's review checks the shared code style and clean code (short functions, clear names, no repeated logic), and says exactly which macro test checks are wanted. SonarQube Cloud keeps tests apart from sources and leaves coverage to Codecov, Codecov reports through statuses only, and `CODE_STYLE.md` no longer contradicts itself on macro tests. The review uses the chill profile and reports broken style and testing rules inline as should-fix findings, so an open one blocks the merge.
- Every test has a display name that states what it checks, such as "A spy keeps every input in order", so a test report reads as a list of what the package promises. Test function names stay as they were, for `swift test --filter`.

### Fixed

- The code `@GenerateSpies` writes names every type it uses with its module (`Understudy.Spy`, `Understudy.PropertySpy`, `Swift.Void`, `_Concurrency.TaskLocal` and the rest), so a double still builds next to a type of the test's own called `Spy`, `Void` or `TaskLocal`. `@Sample`'s defaults keep the type as the property writes it, so they follow a type of the app's own called `Date` or `URL`.

## 0.6.0 - 2026-11-25

### Added

- Typed throws: `@GenerateSpies` writes a requirement such as `func signIn(...) async throws(AuthError) -> Account`. It gets a `ThrowingSpy`, as a plain `throws` does, and its body rethrows the scripted error as `AuthError`. An error of another type stops the test with a message naming the spy and both types. `throws(any Error)` is a plain `throws`, and `throws(Never)` throws nothing.
- Generics inside a collection: a generic parameter inside an array, an optional, a dictionary's value or a set, such as `func tags<T: Tag>(_ items: [T]) -> [T]`, is recorded as the same container of `any` of its constraints (`[any Tag]`; a set as `Set<AnyHashable>`), and a returned one is cast back to the type the caller asks for. A generic parameter inside a closure, a tuple or another generic type is still refused.
- `@SpiedProperty` with a first value: `@SpiedProperty var user: String = "ana"` starts its spy with `"ana"`, and the double's initializer doesn't ask for it. It works in a `Sendable` class and in an actor, where `@Recorded` can't. Without a value it works as before.
- Subscripts: in a `@GenerateSpies` class, `subscript(index: Int) -> Item { @Spied get {} @Spied set {} }` (Swift needs the empty bodies; Swift 6.4 or later), and a protocol's subscript requirements (every Swift version). Gets go to `subscriptSpy`, a `Spy` of the index, and sets to `subscriptSetSpy`, a `Spy` of the index and the `newValue`; a get-only subscript has only the first. Several indices are a labelled tuple, and overloads add the index names. The double's initializer asks for the first answer unless it is optional.
- Static members: `@Spied static func` and `@SpiedProperty static var`, and a protocol's static requirements. The static spies live in a box held in a task local, and `.freshSpies(SpyClock.self)`, a Swift Testing trait for a test or a suite (Swift 6.1 or later), gives each test its own, so parallel tests never share them. Without the trait, every test shares one box. A static spy starts from the obvious first answer (`nil`, `""`, `0`, `false`, empty), and a static requirement with none is refused. A double with static spies conforms to the new `StaticSpies`, whose `withFreshSpies` runs a block with a fresh box.
- Fix-its: each refusal with one clear fix offers it in the editor: `let` to `var` for a `@SpiedProperty`, removing a `@Spied` function's body, naming a parameter written `_: Int`, adding `: <#Type#>` to a property with no type, and `@Recorded` to `@SpiedProperty` in an actor.
- `@GenerateSpies` refuses `@Recorded` in a `Sendable` class, which can't hold a wrapped property, with a fix-it to `@SpiedProperty`.

### Changed

- The double's initializer gives an obvious first answer when the test passes none: `""` for `String`, `0` for whole and decimal numbers and `Decimal`, `false` for `Bool`, and empty arrays, dictionaries and sets. `SpyCatalog()` now compiles when every answer has one. A type with no obvious answer is still a required argument, and every argument a test passes today is still accepted. The macro reads the type as written, so `Swift.String` or a typealias stays required.
- The README is rewritten for a first-time user: what Understudy is (spies and sample values), install, a quick start, then each tool with one short example. Every example is compiled and run against the current API.

## 0.5.0 - 2026-11-25

### Added

- `@Sample`, in the new product `UnderstudySamples`: on a struct, it writes `static func sample(...)`, with one parameter per stored property, each with a default, so a test gets a complete value in one call, such as `Product.sample(price: 0)`. `@SampleDefault(value)` sets a property's default. The sample is written for debug builds only, and is as visible as the struct.
- `CallOrder { ... }`, which watches every spy in a block of `Watched(spy, as: name)` lines, for `Spy` and `ThrowingSpy` alike. `watch(_:as:)` stays, for a spy the test starts watching later.
- `@Recorded`, a property wrapper that spies on a property whose first value is at its declaration: `@Recorded var user = "ana"`, with `$user` its `PropertySpy`. It works in doubles written by hand and in `@GenerateSpies` classes, next to `@SpiedProperty`, and a `@GenerateSpies` class may have `@Recorded` properties only. `@GenerateSpies` refuses it on an actor, where `@SpiedProperty` is the way.

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
