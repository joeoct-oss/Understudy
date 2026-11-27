# How to review an Understudy pull request

Gitar reviews beside CodeRabbit. It never approves, never writes commits and never edits the
pull request description, but it gates the merge: any finding of important severity or higher
requests changes, and its "Gitar" check is required on `main`. So rate a finding important only
when it is a blocker or a should-fix item below. Every merge to `main` publishes a release, so a
change reaches package users at once.

- Report only blockers and should-fix items, each as one inline comment that names the rule it
  breaks and why. Breaking a code style rule is a should-fix item. No praise, no recaps and no
  nitpicks the code style doesn't ask for.
- Look hardest at what the linters and SonarQube Cloud can't see: logic and behaviour bugs,
  changes to the code the macros generate or to their diagnostics, locking and waiting code,
  breaking public API changes, and tests that would pass with the bug.
- Code style, including docs and examples. `CODE_STYLE.md` holds this package's own rules and
  links to the shared rules, which live outside this repo. The shared rules a diff can show are
  restated in the `path_instructions` of `.coderabbit.yaml`: apply those too, and ignore its
  CodeRabbit-only settings.

@CODE_STYLE.md

@.coderabbit.yaml
