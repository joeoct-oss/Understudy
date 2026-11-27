---
title: "Macros refuse with a diagnostic, never a crash"
description: "Every macro path the user's syntax can reach ends in code or a diagnostic"
type: check
when: "PRs that change Swift files under Sources/UnderstudyMacros/ or Sources/UnderstudySamplesMacros/"
actions: "Mark the check unmet and name each file and line that breaks it"
---

# Macros refuse with a diagnostic, never a crash

The macros run as a compiler plugin inside the user's build, so a crash there breaks their build
with no message. `CODE_STYLE.md` ("Macros write what a person would") is the home of this rule.

The check is met when every changed macro file keeps all of these:

- No `fatalError`, `preconditionFailure`, `try!`, `as!` or force-unwrap on syntax that came
  from the user. A shape the macro can't write throws or emits a `Diagnostic` from
  `Sources/UnderstudyMacros/Diagnostics/` whose message says what to write instead, pointing at
  the requirement rather than the attribute whenever there is one. A fix-it is added when the
  correction is mechanical.
- An attached macro's `names:` list in `Sources/Understudy/Macros.swift` names every member the
  macro now generates. A new generated name with no matching `names:` entry fails.
- Generated code names the package's and the standard library's types with their module
  (`Understudy.Spy`, `Swift.Int`), so a user type with the same name can't shadow them.
- No swift-syntax API newer than the lowest version `Package.swift` allows, unless it is behind
  `#if canImport(SwiftSyntaxNNN)`. The lowest-versions Linux job builds this, so cite the API
  and the version it arrived in.
- The plugin only reads the syntax it is given: no file, environment, process or network access.

Braces and spacing inside the code strings a macro emits follow what the expansion needs, not the
source style; don't count those.
