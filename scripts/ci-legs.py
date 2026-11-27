#!/usr/bin/env python3
#
#  ci-legs.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Decides which legs of the checks workflow (checks.yml) a pull request's run needs, so a change
runs only the checks that read the files it touched (Yousef, 2026-11-27). The legs are the Linux
checks, the Apple platform checks, the benchmarks and mutation testing. LEG_RULES below, their one
home, says which files each leg reads.

A leg is skipped in two cases:
- Nothing it reads changed in the pull request: every file in the diff from the base is one no
  leg reads (Markdown at the root, LICENSE, .gitignore, review tool config and the like) or one
  only other legs read.
- It already passed on an earlier commit of this pull request, and nothing it reads changed
  since. This is what a merge from main that brings only docs or config gets: the tests that
  passed before the merge stay valid. The earlier commits are the pull request's own, followed by
  first parent from the head, newest first, up to MAX_COMMITS; the result is the leg's check run on
  that commit, read with the run's GITHUB_TOKEN.
A file that no rule names reads as every leg's, so a new kind of file runs everything until it is
given a rule. A push to main, or any failure to read the diff, runs every leg.

A skipped Linux or Apple leg still reports its required gate, as a pass (ci.yml, apple.yml), and
the Apple leg still runs the CodeQL Swift scan, which the code scanning rule waits for on every
commit. The other jobs of a skipped leg don't run.

Writes `<leg>=true|false` lines to GITHUB_OUTPUT and a table of the decisions to
GITHUB_STEP_SUMMARY, when those are set. Python 3, nothing else.

Usage: ci-legs.py                reads BASE_SHA, HEAD_SHA, GITHUB_REPOSITORY, GITHUB_TOKEN
       ci-legs.py --self-check   runs its own cases and exits
"""

import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

LINUX, APPLE, BENCHMARKS, MUTATION = "linux", "apple", "benchmarks", "mutation"
LEGS = (LINUX, APPLE, BENCHMARKS, MUTATION)
ALL = frozenset(LEGS)

# The first rule whose pattern matches a changed path gives the legs that read it. A path no rule
# matches reads as every leg's: the package's sources, tests and manifests fall there on purpose,
# as do checks.yml and this script, which decide how every leg runs.
LEG_RULES = [
    # Read by no leg: docs, review tool config, and workflows and scripts no leg calls on a pull
    # request (the fast checks and SonarQube run on every pull request anyway).
    (r"[^/]+\.md|LICENSE|\.gitignore|\.coderabbit\.yaml|\.spi\.yml|codecov\.yml", set()),
    (r"sonar-project\.properties|\.gitar/.*", set()),
    (r"\.github/(dependabot\.yml|pull_request_template\.md|assets/.*)", set()),
    (r"\.github/workflows/(branch-name|pr-rules|codeql|security-alerts|stress|release|cache)\.yml",
     set()),
    (r"scripts/(check-pr-rules\.py|check-structure\.py|post-security-alerts\.sh|release-notes\.sh"
     r"|sonar-scan\.sh)", set()),
    # One leg each.
    (r"\.github/workflows/ci\.yml|\.github/api-breakage-allowlist\.txt|Swift5Mode/.*", {LINUX}),
    (r"scripts/(check-coverage|check-generated-code)\.sh", {LINUX}),
    (r"\.github/workflows/apple\.yml|ApplePlatforms/.*|scripts/install-tuist\.sh", {APPLE}),
    (r"\.github/workflows/benchmarks\.yml|scripts/benchmark\.sh", {BENCHMARKS}),
    (r"\.github/workflows/mutation\.yml|scripts/mutate\.py", {MUTATION}),
    # The generated code budget (Linux) and the benchmarks both build these.
    (r"Benchmarks/.*|Tools/.*|scripts/compare-expansions\.sh", {LINUX, BENCHMARKS}),
]
COMPILED_RULES = [(re.compile(pattern), frozenset(legs)) for pattern, legs in LEG_RULES]

# Each leg's check run, as GitHub names a job of a called workflow: "<caller> / <job>".
CHECK_NAMES = {
    LINUX: "Linux checks / Linux build and tests",
    APPLE: "Apple platform checks / Apple builds and tests",
    BENCHMARKS: "Benchmarks / Benchmarks (Swift 6.4)",
    MUTATION: "Mutation testing / Mutation testing (Swift 6.4)",
}
MAX_COMMITS = 15


def legs_reading(path):
    for pattern, legs in COMPILED_RULES:
        if pattern.fullmatch(path):
            return legs
    return ALL


def legs_for(paths):
    """The legs that read at least one of the paths."""
    needed = set()
    for path in paths:
        needed |= legs_reading(path)
    return needed


def changed_files(old, new):
    """The paths that differ between two commits. A rename counts as a deletion and an addition,
    so moving a file out of a leg's reach still runs that leg."""
    out = subprocess.run(["git", "diff", "--no-renames", "--name-only", old, new],
                         check=True, capture_output=True, text=True).stdout
    return [line for line in out.splitlines() if line]


def earlier_commits(head, base):
    """The pull request's own earlier commits, newest first, following first parents from the
    head and stopping at the first one main already has."""
    out = subprocess.run(["git", "rev-list", "--first-parent", f"--max-count={MAX_COMMITS + 1}",
                          head], check=True, capture_output=True, text=True).stdout
    commits = []
    for sha in out.split()[1:]:
        on_main = subprocess.run(["git", "merge-base", "--is-ancestor", sha, base]).returncode == 0
        if on_main:
            break
        commits.append(sha)
    return commits


def check_passed(repo, token, sha, leg):
    """Whether the leg's latest check run on the commit passed."""
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    query = urllib.parse.urlencode({"check_name": CHECK_NAMES[leg], "filter": "latest"})
    request = urllib.request.Request(
        f"{api}/repos/{repo}/commits/{sha}/check-runs?{query}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=20) as response:
        runs = json.load(response)["check_runs"]
    return any(run.get("conclusion") == "success" for run in runs)


def decide(changed, earlier, passed, delta):
    """Maps each leg to (runs, reason). `changed` is the pull request's diff from its base,
    `earlier` its earlier commits newest first, `passed(sha, leg)` whether the leg passed there,
    and `delta(sha)` the files changed between that commit and the head."""
    needed = legs_for(changed)
    decisions = {}
    for leg in LEGS:
        if leg not in needed:
            decisions[leg] = (False, "nothing it reads changed in this pull request")
            continue
        decisions[leg] = (True, "files it reads changed")
        for sha in earlier:
            if passed(sha, leg):
                if leg not in legs_for(delta(sha)):
                    decisions[leg] = (False, f"passed on {sha[:7]}, and nothing it reads changed "
                                             "since")
                break
    return decisions


def run():
    base, head = os.environ.get("BASE_SHA", ""), os.environ.get("HEAD_SHA", "")
    if not base or not head:
        return {leg: (True, "not a pull request") for leg in LEGS}
    repo, token = os.environ["GITHUB_REPOSITORY"], os.environ.get("GITHUB_TOKEN", "")
    changed = changed_files(base, "HEAD")
    print("Changed files:", *changed, sep="\n  ")

    def passed(sha, leg):
        try:
            return bool(token) and check_passed(repo, token, sha, leg)
        except (OSError, ValueError, KeyError) as error:
            print(f"Couldn't read {leg} on {sha[:7]}, so it counts as not passed: {error}")
            return False

    def delta(sha):
        return changed_files(sha, "HEAD")

    return decide(changed, earlier_commits(head, base), passed, delta)


def report(decisions):
    lines = ["## Which checks run", "", "| Checks | Run | Why |", "| --- | --- | --- |"]
    for leg, (runs, reason) in decisions.items():
        lines.append(f"| {leg} | {'yes' if runs else 'skipped'} | {reason} |")
        print(f"{leg}: {'runs' if runs else 'skipped'}, {reason}")
    for name, text in (("GITHUB_OUTPUT", [f"{leg}={str(r).lower()}" for leg, (r, _) in
                                          decisions.items()]),
                       ("GITHUB_STEP_SUMMARY", lines)):
        if os.environ.get(name):
            with open(os.environ[name], "a", encoding="utf-8") as out:
                out.write("\n".join(text) + "\n")


def self_check():
    cases = [
        (["CHANGELOG.md", ".gitignore"], set()),
        (["README.md", "LICENSE", ".gitar/review/rules.md", ".coderabbit.yaml"], set()),
        (["docs/guide.md"], ALL),
        (["Sources/Understudy/Spy.swift"], ALL),
        (["Tests/UnderstudyTests/SpyTests.swift"], ALL),
        (["Package.resolved"], ALL),
        ([".github/workflows/checks.yml"], ALL),
        (["scripts/ci-legs.py"], ALL),
        ([".github/workflows/apple.yml"], {APPLE}),
        (["ApplePlatforms/Tuist.swift"], {APPLE}),
        ([".github/workflows/ci.yml", "Swift5Mode/Package.swift"], {LINUX}),
        ([".github/workflows/codeql.yml", "scripts/sonar-scan.sh"], set()),
        (["scripts/mutate.py"], {MUTATION}),
        (["Benchmarks/generated-code-budget.txt"], {LINUX, BENCHMARKS}),
        (["Sources/a.md/x.swift"], ALL),
    ]
    failures = [(paths, legs_for(paths), want) for paths, want in cases if legs_for(paths) != want]

    passed_on = {"c1": {LINUX, APPLE}}
    deltas = {"c1": [".gitignore", "CHANGELOG.md"], "c2": ["Sources/a.swift"]}
    code = ["Sources/a.swift"]
    flows = [
        # A merge from main that brings only docs reuses what passed on the commit before it.
        (code, ["c1"], {LINUX: False, APPLE: False, BENCHMARKS: True, MUTATION: True}),
        # A newer commit that changed code runs again, even if an older one passed.
        (code, ["c2", "c1"], {LINUX: True, APPLE: True, BENCHMARKS: True, MUTATION: True}),
        # The first push of a docs-only pull request runs no leg.
        (["README.md"], [], {LINUX: False, APPLE: False, BENCHMARKS: False, MUTATION: False}),
    ]
    passed_on["c2"] = {LINUX, APPLE}
    for changed, earlier, want in flows:
        got = decide(changed, earlier, lambda sha, leg: leg in passed_on.get(sha, set()),
                     lambda sha: deltas[sha])
        runs = {leg: decision[0] for leg, decision in got.items()}
        if runs != want:
            failures.append((changed, earlier, runs, want))
    for failure in failures:
        print("Self-check failed:", *failure)
    print(f"{len(cases) + len(flows) - len(failures)} of {len(cases) + len(flows)} cases passed.")
    return 1 if failures else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        sys.exit(self_check())
    try:
        decisions = run()
    except (subprocess.CalledProcessError, OSError) as error:
        print(f"::warning::Couldn't work out the changed files, so every check runs: {error}")
        decisions = {leg: (True, "changed files unknown") for leg in LEGS}
    report(decisions)
