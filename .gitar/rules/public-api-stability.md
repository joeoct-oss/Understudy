---
title: "Breaking changes are recorded"
description: "Every merge to main is a release, so a break in the public API or in generated code must be in CHANGELOG.md"
type: check
when: "PRs that change Swift files under Sources/, or Package.swift"
actions: "Mark the check unmet and name each breaking change that CHANGELOG.md doesn't record as breaking"
---

# Breaking changes are recorded

Every merge to `main` publishes a release, so a change reaches package users at once.

A change is breaking when it:

- removes or renames a `public` or `open` declaration, or changes its signature, argument label,
  default argument, generic constraints or isolation;
- drops a public protocol conformance, `Sendable` included;
- adds a protocol requirement without a default, or a case to a public enum;
- changes what a public macro generates in a way user code can see: a member's name, type,
  access level or isolation, a removed member, a shape the macro used to accept and now
  refuses, or what a generated member records, answers or throws;
- raises a platform minimum, `swift-tools-version` or the lowest swift-syntax in `Package.swift`.

The check is met when the PR has no breaking change, or `CHANGELOG.md` gains an entry under
`## Unreleased` that says the change is breaking and what users change. Additions alone pass.
