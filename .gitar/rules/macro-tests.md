---
title: "Macro changes come with behaviour tests"
description: "A change to what the macros accept, refuse or generate is pinned by a test a person can read"
type: check
when: "PRs that change Swift files under Sources/UnderstudyMacros/ or Sources/UnderstudySamplesMacros/"
actions: "Mark the check unmet and name the accepted or refused shape that has no test"
---

# Macro changes come with behaviour tests

`CODE_STYLE.md` ("Tests prove behaviour, and every line is tested") is the home of this rule.
This package does not compare expanded text: never ask for `assertMacroExpansion` with
`expandedSource`, or any whole-expansion comparison.

The check is met when:

- Each shape the spy macros newly accept is added to the accepted doubles in
  `Tests/UnderstudyMacrosTests/Fixtures/`, and a test in `Tests/UnderstudyTests/` uses it in
  source so the compiler builds the generated double, and checks what it records and answers.
- `@Sample` writes no double, so a shape it newly accepts is pinned in `SampleExpansionTests`,
  and the sample value it builds in `Tests/UnderstudySamplesTests/SampleTests.swift`.
- Each new refusal or changed diagnostic is in the refused doubles or shapes, with its message,
  line, column and any fix-it and the code that fix-it gives.
- A test checks expanded text only for what a running test can't show: a stop message, the
  generated initializer's parameters, the access level, the `#if DEBUG` wrapper, or a member that
  must not exist.
- A change that alters what a macro writes but no test changed is explained in the description,
  for example a pure refactor that keeps `scripts/compare-expansions.sh` output the same.
