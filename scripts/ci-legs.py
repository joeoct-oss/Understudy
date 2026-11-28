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
  since, on the pull request or on the base (base_changes), and, for the Linux leg, no release
  was published since the workflow run of that pass began, as its public API check compares
  with the latest release (latest_release and check_passed; a release tagged on a commit the
  pull request already has counts too). This is what a merge from main that brings only root
  Markdown or config gets: the tests that passed before the merge stay valid. A DocC catalog
  file or scripts/build-docs.sh is the Linux leg's, which builds the docs, so a merge that
  brings one runs that leg again instead of reusing its pass. The earlier commits are the
  pull request's own, followed by first parent from the head, newest first, up to MAX_COMMITS;
  the result is the leg's check run on that commit, made by GitHub Actions and read with the
  run's GITHUB_TOKEN.
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

import datetime
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

LINUX, APPLE, BENCHMARKS, MUTATION = "linux", "apple", "benchmarks", "mutation"
LEGS = (LINUX, APPLE, BENCHMARKS, MUTATION)
ALL = frozenset(LEGS)

# The first rule whose pattern matches a changed path gives the legs that read it. A path no rule
# matches reads as every leg's: the package's sources, tests and manifests fall there on purpose,
# as do checks.yml and this script, which decide how every leg runs.
LEG_RULES = [
    # Read by no leg: root Markdown, review tool config, and workflows and scripts no leg calls on
    # a pull request (the fast checks and SonarQube run on every pull request anyway).
    (r"[^/]+\.md|LICENSE|\.gitignore|\.coderabbit\.yaml|\.spi\.yml|codecov\.yml", set()),
    (r"sonar-project\.properties|\.gitar/.*", set()),
    # The lint config and scripts: lint runs in the fast checks on every pull request.
    (r"\.swift-format|\.swiftlint\.yml|\.swiftlint-baseline\.json", set()),
    (r"scripts/(lint|lint-tools|format)\.sh", set()),
    (r"\.github/(dependabot\.yml|pull_request_template\.md|assets/.*)", set()),
    ((r"\.github/workflows/(branch-name|pr-rules|codeql|security-alerts|stress|release|cache"
      r"|delete-unused-claude-branches|publish-github-text)\.yml"), set()),
    ((r"scripts/(check-pr-rules\.py|check-structure\.py|post-security-alerts\.sh|release-notes\.sh"
      r"|sonar-scan\.sh|check-doc-examples\.py|delete-unused-claude-branches\.py"
      r"|publish-github-text\.py)"), set()),
    # One leg each.
    (r"\.github/workflows/ci\.yml|\.github/api-breakage-allowlist\.txt|Swift5Mode/.*", {LINUX}),
    (r"scripts/(check-coverage|check-generated-code)\.sh", {LINUX}),
    # The DocC catalog: only the Linux leg's docs job builds it, and the fast checks compare its
    # examples with the guide tests on every pull request.
    (r"Sources/Understudy/Understudy\.docc/.*|scripts/build-docs\.sh", {LINUX}),
    (r"\.github/workflows/apple\.yml|ApplePlatforms/.*|scripts/install-tuist\.sh", {APPLE}),
    (r"\.github/workflows/benchmarks\.yml|scripts/benchmark\.sh", {BENCHMARKS}),
    (r"\.github/workflows/mutation\.yml|scripts/mutate\.py", {MUTATION}),
    # The generated code budget (Linux) and the benchmarks both build these.
    (r"Benchmarks/.*|Tools/.*|scripts/compare-expansions\.sh", {LINUX, BENCHMARKS}),
]
# Stands for a release tagged on the base, which the Linux leg's public API check compares with.
NEW_RELEASE = "<new release tag>"
LEG_RULES.append((re.escape(NEW_RELEASE), {LINUX}))
COMPILED_RULES = [(re.compile(pattern), frozenset(legs)) for pattern, legs in LEG_RULES]

# Each leg's check run, as GitHub names a job of a called workflow: "<caller> / <job>".
CHECK_NAMES = {
    LINUX: "Linux checks / Linux build and tests",
    APPLE: "Apple platform checks / Apple builds and tests",
    BENCHMARKS: "Benchmarks / Benchmarks (Swift 6.4)",
    MUTATION: "Mutation testing / Mutation testing (Swift 6.4)",
}
MAX_COMMITS = 15
# How long all check-run lookups together may take, in seconds, well inside the fast job's
# 5-minute limit. Past it, every leg not yet shown to have passed runs.
LOOKUP_BUDGET = 60
# GitHub Actions' own app: a check run counts only when Actions made it, so no other app or
# integration can stand in for a leg that passed.
ACTIONS_APP_ID = 15368
# The form GitHub writes its timestamps in, which sorts in time order as text.
API_TIME = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ")


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


def git(*args, check=True):
    """Runs git with an argument list and no shell. git comes from the runner's PATH, and the
    arguments are fixed flags and commit SHAs from the event or from git itself."""
    return subprocess.run(["git", *args], check=check, capture_output=True,  # noqa: S603, S607
                          text=True)


def changed_files(old, new):
    """The paths that differ between two commits. A rename counts as a deletion and an addition,
    so moving a file out of a leg's reach still runs that leg."""
    out = git("diff", "--no-renames", "--name-only", old, new).stdout
    return [line for line in out.splitlines() if line]


def base_changes(sha, base):
    """Every path a commit on the base touched since the commit forked from it. A run checks out
    the commit merged with the base of its time, which this can't see, so every base change since
    the fork counts, even one undone later: a pass is reused only when no base it could have been
    merged with changed what a leg reads."""
    fork = git("merge-base", sha, base).stdout.strip()
    # A merge's own changes count too: by default git log lists no files for a merge.
    out = git("log", "--no-renames", "--diff-merges=first-parent", "--format=", "--name-only",
              f"{fork}..{base}").stdout
    paths = {line for line in out.splitlines() if line}
    # A release tagged on the base since the fork changes what the public API check compares
    # with, though no file changed.
    tags = git("tag", "--merged", base, "--no-merged", fork).stdout
    if tags.split():
        paths.add(NEW_RELEASE)
    return sorted(paths)


def earlier_commits(head, base):
    """The pull request's own earlier commits, newest first, following first parents from the
    head and stopping at the first one main already has."""
    out = git("rev-list", "--first-parent", f"--max-count={MAX_COMMITS + 1}", head).stdout
    commits = []
    for sha in out.split()[1:]:
        on_main = git("merge-base", "--is-ancestor", sha, base, check=False).returncode == 0
        if on_main:
            break
        commits.append(sha)
    return commits


def api_get(token, path):
    """GETs a path of the GitHub API as JSON. The API's address must be HTTPS, so no other scheme
    reaches urlopen."""
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    if not api.startswith("https://"):
        raise ValueError(f"GITHUB_API_URL isn't HTTPS: {api}")
    request = urllib.request.Request(  # noqa: S310 - the scheme is checked above
        f"{api}{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310 - checked above
        data = json.load(response)
    if not isinstance(data, dict):
        # ValueError, not TypeError: a bad answer is a failed lookup, which passed() handles.
        raise ValueError(f"The API's answer for {path} isn't a JSON object")  # noqa: TRY004
    return data


def latest_release(repo, token):
    """When the latest release was published, as the API writes it ("" with no release yet)."""
    try:
        return api_time(api_get(token, f"/repos/{repo}/releases/latest").get("published_at"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return ""
        raise


def api_time(value):
    """An API timestamp, checked to be one so that comparing them as text orders them in time.
    Anything else raises ValueError, which counts as a failed lookup, so the leg runs."""
    if not isinstance(value, str) or not API_TIME.fullmatch(value):
        raise ValueError(f"{value!r} isn't a GitHub API timestamp")
    datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")  # noqa: DTZ007 - checks the date only
    return value


def check_passed(repo, token, sha, leg, since=""):
    """Whether the leg's latest check run on the commit, made by GitHub Actions, passed in a
    workflow run that began at or after `since` (an API timestamp; these compare as text). The
    gate's own check run starts only after its leg's jobs, so the time that counts is when its
    check suite, the whole workflow run, was created: before the run checked out the tags its
    public API check compares with, and before it decided whether to skip."""
    query = urllib.parse.urlencode({"check_name": CHECK_NAMES[leg], "filter": "latest",
                                    "app_id": ACTIONS_APP_ID})
    runs = api_get(token, f"/repos/{repo}/commits/{sha}/check-runs?{query}").get("check_runs")
    if not isinstance(runs, list) or not all(isinstance(run, dict) for run in runs):
        raise ValueError(f"The check runs for {sha[:7]} aren't a list of objects")
    if not since:
        return any_passed(runs)

    def began(run):
        suite = run.get("check_suite")
        if not isinstance(suite, dict) or "id" not in suite:
            raise ValueError(f"A check run on {sha[:7]} names no check suite")
        return api_time(api_get(token, f"/repos/{repo}/check-suites/{suite['id']}")
                        .get("created_at"))

    return any_passed(runs, since, began)


def any_passed(runs, since="", began=lambda run: ""):
    """Whether one of the check runs passed in a workflow run that `began` at or after `since`."""
    return any(run.get("conclusion") == "success" and (not since or began(run) >= since)
               for run in runs)


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
                    decisions[leg] = (False, (f"passed on {sha[:7]}, and nothing it reads "
                                              "changed since"))
                break
    return decisions


def run():
    base, head = os.environ.get("BASE_SHA", ""), os.environ.get("HEAD_SHA", "")
    if not base or not head:
        return {leg: (True, "not a pull request") for leg in LEGS}
    repo, token = os.environ["GITHUB_REPOSITORY"], os.environ.get("GITHUB_TOKEN", "")
    changed = changed_files(base, "HEAD")
    print("Changed files:", *changed, sep="\n  ")

    # One failed lookup, or the lookups running past LOOKUP_BUDGET, stops the rest, so a slow or
    # broken API can't hold the job past its timeout: every leg not yet shown to have passed runs.
    lookups = {"failed": False, "deadline": time.monotonic() + LOOKUP_BUDGET, "release": None}

    def passed(sha, leg):
        if lookups["failed"] or not token:
            return False
        if time.monotonic() > lookups["deadline"]:
            lookups["failed"] = True
            print(f"Check-run lookups took over {LOOKUP_BUDGET} s, so the rest count as not "
                  "passed.", file=sys.stderr)
            return False
        try:
            # A Linux pass counts only if it started after the latest release was published,
            # since its public API check compares with that release.
            if leg == LINUX and lookups["release"] is None:
                lookups["release"] = latest_release(repo, token)
            since = lookups["release"] if leg == LINUX else ""
            return check_passed(repo, token, sha, leg, since)
        except (OSError, ValueError, KeyError, TypeError) as error:
            lookups["failed"] = True
            print(f"Couldn't read {leg} on {sha[:7]}, so it and every later lookup count as not "
                  f"passed: {error}", file=sys.stderr)
            return False

    def delta(sha):
        return changed_files(sha, "HEAD") + base_changes(sha, base)

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


def merge_change_counts():
    """Builds a small repository where one merge on the base changes a source file and a later
    merge undoes it, and checks that base_changes still lists the file."""
    with tempfile.TemporaryDirectory() as repo:
        def run_git(*args):
            return git("-C", repo, "-c", "user.name=Check",
                       "-c", "user.email=check@example.invalid",
                       "-c", "commit.gpgsign=false", *args).stdout.strip()

        def write(path, text):
            target = pathlib.Path(repo, path)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")

        run_git("init", "-q", "-b", "main")
        write("Sources/a.swift", "one\n")
        run_git("add", ".")
        run_git("commit", "-qm", "fork")
        run_git("checkout", "-qb", "feature")
        write("README.md", "feature\n")
        run_git("add", ".")
        run_git("commit", "-qm", "feature")
        sha = run_git("rev-parse", "HEAD")
        for step, text in (("1", "changed\n"), ("2", "one\n")):
            run_git("checkout", "-q", "main")
            run_git("checkout", "-qb", f"side{step}")
            write(f"side{step}.md", step)
            run_git("add", ".")
            run_git("commit", "-qm", f"side {step}")
            run_git("checkout", "-q", "main")
            run_git("merge", "-q", "--no-ff", "--no-commit", f"side{step}")
            write("Sources/a.swift", text)
            run_git("add", ".")
            run_git("commit", "-qm", f"merge {step}")
        base = run_git("rev-parse", "main")
        here = os.getcwd()
        os.chdir(repo)  # base_changes runs git in the working directory.
        try:
            return "Sources/a.swift" in base_changes(sha, base)
        finally:
            os.chdir(here)


# Paths and the legs that read them, for the self-check.
CLASSIFY_CASES = [
    (["CHANGELOG.md", ".gitignore"], set()),
    (["README.md", "LICENSE", ".gitar/review/rules.md", ".coderabbit.yaml"], set()),
    ([".swiftlint.yml", ".swift-format", "scripts/lint.sh"], set()),
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
    ([".github/workflows/delete-unused-claude-branches.yml",
      "scripts/delete-unused-claude-branches.py"], set()),
    (["Sources/Understudy/Understudy.docc/Articles/Guide.md", "scripts/build-docs.sh"], {LINUX}),
    (["Sources/Understudy/Understudy.docc/Resources/step.swift"], {LINUX}),
    (["scripts/check-doc-examples.py"], set()),
    ([".github/workflows/publish-github-text.yml", "scripts/publish-github-text.py"], set()),
    (["scripts/mutate.py"], {MUTATION}),
    (["Benchmarks/generated-code-budget.txt"], {LINUX, BENCHMARKS}),
    (["Sources/a.md/x.swift"], ALL),
    ([NEW_RELEASE, "CHANGELOG.md"], {LINUX}),
]

# The pull request's changed files, its earlier commits and which legs run, for the self-check.
# c1 and c2 passed the Linux and Apple legs; c1 is followed only by root Markdown, c2 by code.
CODE = ["Sources/a.swift"]
FLOW_CASES = [
    # A merge from main that brings only root Markdown or config reuses what passed on the commit
    # before it.
    (CODE, ["c1"], {LINUX: False, APPLE: False, BENCHMARKS: True, MUTATION: True}),
    # A newer commit that changed code runs again, even if an older one passed.
    (CODE, ["c2", "c1"], {LINUX: True, APPLE: True, BENCHMARKS: True, MUTATION: True}),
    # The first push of a pull request that changes only root Markdown or config runs no leg.
    (["README.md"], [], {LINUX: False, APPLE: False, BENCHMARKS: False, MUTATION: False}),
]
FLOW_PASSES = {"c1": {LINUX, APPLE}, "c2": {LINUX, APPLE}}
FLOW_DELTAS = {"c1": [".gitignore", "CHANGELOG.md"], "c2": ["Sources/a.swift"]}


def classification_failures():
    return [(paths, legs_for(paths), want) for paths, want in CLASSIFY_CASES
            if legs_for(paths) != want]


def flow_failures():
    failures = []
    for changed, earlier, want in FLOW_CASES:
        got = decide(changed, earlier, lambda sha, leg: leg in FLOW_PASSES.get(sha, set()),
                     lambda sha: FLOW_DELTAS[sha])
        runs = {leg: decision[0] for leg, decision in got.items()}
        if runs != want:
            failures.append((changed, earlier, runs, want))
    return failures


def release_failures():
    """A pass from a workflow run that began before the latest release doesn't count for the
    Linux leg, even when its gate's check run started after the release."""
    runs = [{"conclusion": "success", "started_at": "2026-11-27T12:00:00Z", "suite": "10:00"}]

    def began(run):
        return f"2026-11-27T{run['suite']}:00Z"

    cases = [(runs, "", True), (runs, "2026-11-27T09:00:00Z", True),
             (runs, "2026-11-27T11:00:00Z", False), ([{"conclusion": "failure"}], "", False)]
    failures = [("release", since, want) for runs, since, want in cases
                if any_passed(runs, since, began) != want]
    for value, valid in [("2026-11-27T10:00:00Z", True), ("unavailable", False), (None, False),
                         ("", False), ("2026-11-27 10:00:00", False),
                         ("9999-99-99T99:99:99Z", False), ("2026-02-30T10:00:00Z", False)]:
        try:
            api_time(value)
            ok = True
        except ValueError:
            ok = False
        if ok != valid:
            failures.append(("timestamp", value, valid))
    return failures


def self_check():
    failures = classification_failures() + flow_failures() + release_failures()
    if not merge_change_counts():
        failures.append(("a base merge that changes a file and a later one that undoes it",))
    for failure in failures:
        print("Self-check failed:", *failure, file=sys.stderr)
    total = len(CLASSIFY_CASES) + len(FLOW_CASES) + 4 + 7 + 1
    print(f"{total - len(failures)} of {total} cases passed.")
    return 1 if failures else 0


def main():
    if sys.argv[1:] == ["--self-check"]:
        return self_check()
    try:
        decisions = run()
    except (subprocess.CalledProcessError, OSError) as error:
        print(f"::warning::Couldn't work out the changed files, so every check runs: {error}")
        decisions = {leg: (True, "changed files unknown") for leg in LEGS}
    report(decisions)
    return 0


if __name__ == "__main__":
    sys.exit(main())
