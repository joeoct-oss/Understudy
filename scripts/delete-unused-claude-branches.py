#!/usr/bin/env python3
#
#  delete-unused-claude-branches.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Deletes the claude/ branches that no open pull request uses (Yousef, 2026-11-28).

Cloud work pushes to its own claude/ branch, then fast-forwards a branch named by the branch rule
from it and opens the pull request from that one. GitHub's "Automatically delete head branches"
never removes the claude/ branch, since it is no pull request's head, so this script does. It is
the one home for these rules:

- It looks only at branches under claude/.
- It keeps a branch whose head commit is the head commit of an open pull request, or that is an
  open pull request's head branch by name. The commit is what links the two, because the branch
  the pull request is opened from has another name.
- It keeps a branch whose head commit is less than MINIMUM_AGE_HOURS old, so work that is still
  going isn't hit between its push and its fast-forward.
- It deletes the rest with a git push that names the commit it checked, so a branch pushed to
  after the check is left alone. A delete that fails doesn't stop the others; the run then fails.
- The run summary lists each deleted branch with its commit as it goes, so one can be put back
  from that commit.

The same file is in every repo. Python 3 and git, nothing else.

Usage: delete-unused-claude-branches.py               reads GITHUB_TOKEN, GITHUB_REPOSITORY,
                                                      DRY_RUN ("true" lists and deletes nothing)
       delete-unused-claude-branches.py --self-check  runs its own cases and exits
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import UTC, datetime, timedelta
from pathlib import Path

PREFIX = "claude/"
MINIMUM_AGE_HOURS = 24
MINIMUM_AGE = timedelta(hours=MINIMUM_AGE_HOURS)
NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')
GIT = shutil.which("git") or "git"


def deletable(branches, open_pulls, committed_at, now):
    """The branches to delete, in name order.

    branches maps each claude/ branch to its head commit; open_pulls is a list of (head branch,
    head commit) pairs; committed_at(commit) gives a commit's time, read only for branches no
    open pull request keeps.
    """
    kept_names = {head_branch for head_branch, _ in open_pulls}
    kept_commits = {head_commit for _, head_commit in open_pulls}
    chosen = []
    for name, commit in sorted(branches.items()):
        if name in kept_names or commit in kept_commits:
            continue
        if now - committed_at(commit) < MINIMUM_AGE:
            continue
        chosen.append(name)
    return chosen


def delete_if_unchanged(remote, name, commit, environment=None):
    """Deletes the branch only while it still points at commit. GitHub checks the commit and
    deletes in one step, as for any push, so a branch pushed to since is refused, not deleted.
    Raises subprocess.CalledProcessError when git refuses or fails."""
    ref = f"refs/heads/{name}"
    # The arguments are this script's own, a branch name GitHub listed and its commit.
    subprocess.run(  # noqa: S603
        [GIT, "push", "--porcelain", f"--force-with-lease={ref}:{commit}", remote, f":{ref}"],
        check=True, capture_output=True, env=environment,
    )


def delete_each(branches, names, delete, on_deleted, report):
    """Deletes each named branch, going on past one that fails. Calls on_deleted(name) right
    after each delete and report(message) for each failure. Returns the names that failed."""
    failed = []
    for name in names:
        try:
            delete(name, branches[name])
        except (subprocess.CalledProcessError, OSError) as error:
            detail = getattr(error, "stderr", b"") or b""
            report(f"Could not delete {name}: {error} {detail.decode('utf-8', 'replace').strip()}")
            failed.append(name)
            continue
        on_deleted(name)
    return failed


class GitHub:
    def __init__(self, token, repository):
        self.token = token
        api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
        server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
        self.base = f"{api}/repos/{repository}"
        self.remote = f"{server}/{repository}.git"
        credential = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        # The token goes to git through the environment, never on its command line.
        self.git_environment = {
            **os.environ,
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": f"http.{server}/.extraheader",
            "GIT_CONFIG_VALUE_0": f"AUTHORIZATION: basic {credential}",
        }

    def request(self, url):
        if not url.startswith("https://"):
            raise ValueError(f"Refusing a URL that isn't HTTPS: {url}")
        # Checked above: only HTTPS, to GitHub's API or a Link header GitHub sent.
        request = urllib.request.Request(url, headers={  # noqa: S310
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            return json.loads(response.read()), response.headers.get("Link", "")

    def every_page(self, path):
        items = []
        url = f"{self.base}{path}"
        while url:
            page, link = self.request(url)
            items += page
            next_link = NEXT_LINK.search(link)
            url = next_link.group(1) if next_link else None
        return items

    def claude_branches(self):
        # GitHub matches the start of the name, so heads/claude also finds claude-other.
        refs = self.every_page(f"/git/matching-refs/heads/{PREFIX.rstrip('/')}?per_page=100")
        names = {ref["ref"].removeprefix("refs/heads/"): ref["object"]["sha"] for ref in refs}
        return {name: commit for name, commit in names.items() if name.startswith(PREFIX)}

    def open_pulls(self):
        pulls = self.every_page("/pulls?state=open&per_page=100")
        return [(pull["head"]["ref"], pull["head"]["sha"]) for pull in pulls]

    def committed_at(self, commit):
        details, _ = self.request(f"{self.base}/commits/{commit}")
        return parse_time(details["commit"]["committer"]["date"])

    def delete_branch(self, name, commit):
        delete_if_unchanged(self.remote, name, commit, self.git_environment)


def parse_time(text):
    return datetime.fromisoformat(text)


def report_error(message):
    print(f"::error::{message}", file=sys.stderr)


class Summary:
    """The run summary, written a line at a time, so what was done is there even if a run
    stops part way."""

    def __init__(self):
        path = os.environ.get("GITHUB_STEP_SUMMARY")
        self.path = Path(path) if path else None

    def write(self, text):
        if self.path:
            with self.path.open("a", encoding="utf-8") as summary:
                summary.write(text + "\n")

    def table(self, heading):
        self.write(f"### {heading}\n\n| Branch | Commit |\n| --- | --- |")


def run():
    token = os.environ["GITHUB_TOKEN"]
    repository = os.environ["GITHUB_REPOSITORY"]
    dry_run = os.environ.get("DRY_RUN", "false") == "true"
    github = GitHub(token, repository)
    branches = github.claude_branches()
    chosen = deletable(branches, github.open_pulls(), github.committed_at,
                       datetime.now(UTC))
    print(f"{len(branches)} {PREFIX} branches, {len(chosen)} that no open pull request uses and "
          f"older than {MINIMUM_AGE_HOURS} hours.")
    summary = Summary()
    summary.write(f"{len(branches)} {PREFIX} branches, {len(chosen)} to delete.\n")
    if not chosen:
        return
    summary.table("Would delete (dry run)" if dry_run else "Deleted")

    def record(name):
        print(f"{'Would delete' if dry_run else 'Deleted'} {name} at {branches[name]}")
        summary.write(f"| `{name}` | `{branches[name]}` |")

    if dry_run:
        for name in chosen:
            record(name)
        return
    failed = delete_each(branches, chosen, github.delete_branch, record, report_error)
    if failed:
        summary.write("")
        summary.table("Could not delete")
        for name in failed:
            summary.write(f"| `{name}` | `{branches[name]}` |")
        sys.exit(1)


NOW = datetime(2026, 11, 28, 12, 0, tzinfo=UTC)
OLD = NOW - timedelta(days=3)
COMMIT_TIMES = {"old1": OLD, "old2": OLD, "old3": OLD, "fresh": NOW - timedelta(hours=2),
                "edge": NOW - MINIMUM_AGE}
SELECTION_CASES = [
    # (branches, open pull requests, expected deletions, what it pins)
    ({"claude/thread-one": "old1"}, [], ["claude/thread-one"],
     "an old branch no pull request uses is deleted"),
    ({"claude/thread-one": "old1"}, [("ci/105-cleanup", "old1")], [],
     "a branch whose commit is an open pull request's head is kept, whatever its name"),
    ({"claude/thread-one": "old1"}, [("claude/thread-one", "old2")], [],
     "a branch that is an open pull request's head by name is kept"),
    ({"claude/thread-one": "fresh"}, [], [],
     "a branch with a commit under a day old is kept"),
    ({"claude/thread-one": "edge"}, [], ["claude/thread-one"],
     "a branch whose commit is exactly the minimum age is deleted"),
    ({"claude/thread-two": "old2", "claude/thread-one": "old1", "claude/thread-three": "old3"},
     [("fix/9-thing", "old3")], ["claude/thread-one", "claude/thread-two"],
     "several branches: only the unused ones go, in name order"),
]


def fail(promise, expected, found):
    print(f"FAIL: {promise}: expected {expected}, got {found}", file=sys.stderr)
    return 1


def check_delete_each():
    """A branch that can't be deleted doesn't stop the ones after it."""

    def delete(name, _commit):
        if name == "claude/refused":
            raise subprocess.CalledProcessError(1, "git push", stderr=b"stale info")

    deleted, reports = [], []
    branches = {"claude/before": "old1", "claude/refused": "old2", "claude/after": "old3"}
    failed = delete_each(branches, list(branches), delete, deleted.append, reports.append)
    found = (deleted, failed, len(reports))
    expected = (["claude/before", "claude/after"], ["claude/refused"], 1)
    if found != expected:
        return fail("a refused delete doesn't stop the rest", expected, found)
    return 0


def git_in(directory, *arguments):
    # The arguments are this self-check's own.
    output = subprocess.run(  # noqa: S603
        [GIT, "-C", directory, *arguments], check=True, capture_output=True, text=True,
    )
    return output.stdout.strip()


def check_delete_if_unchanged():
    """Against a local repository: a branch still at the checked commit is deleted, and one
    pushed to after the check is kept."""
    failures = 0
    with tempfile.TemporaryDirectory() as directory:
        remote = str(Path(directory) / "remote.git")
        work = str(Path(directory) / "work")
        subprocess.run([GIT, "init", "-q", "--bare", remote], check=True)  # noqa: S603
        subprocess.run([GIT, "init", "-q", work], check=True)  # noqa: S603
        for setting in (["user.name", "Self check"], ["user.email", "self-check@example.invalid"],
                        ["commit.gpgsign", "false"]):
            git_in(work, "config", *setting)
        git_in(work, "commit", "-q", "--allow-empty", "-m", "first")
        checked = git_in(work, "rev-parse", "HEAD")
        git_in(work, "push", "-q", remote, "HEAD:refs/heads/claude/unchanged",
               "HEAD:refs/heads/claude/moved")
        git_in(work, "commit", "-q", "--allow-empty", "-m", "second")
        git_in(work, "push", "-q", remote, "HEAD:refs/heads/claude/moved")
        delete_if_unchanged(remote, "claude/unchanged", checked)
        try:
            delete_if_unchanged(remote, "claude/moved", checked)
            refused = False
        except subprocess.CalledProcessError:
            refused = True
        left = git_in(remote, "for-each-ref", "--format=%(refname)", "refs/heads").split()
        if left != ["refs/heads/claude/moved"]:
            failures += fail("only a branch still at its checked commit is deleted",
                             ["refs/heads/claude/moved"], left)
        if not refused:
            failures += fail("deleting a branch pushed to since is refused", True, refused)
    return failures


def self_check():
    failures = 0
    for branches, open_pulls, expected, promise in SELECTION_CASES:
        found = deletable(branches, open_pulls, COMMIT_TIMES.__getitem__, NOW)
        if found != expected:
            failures += fail(promise, expected, found)
    parsed = parse_time("2026-11-28T12:00:00Z")
    if parsed != NOW:
        failures += fail("GitHub's Z times are read as UTC", NOW, parsed)
    failures += check_delete_each()
    failures += check_delete_if_unchanged()
    if failures:
        sys.exit(1)
    print(f"All {len(SELECTION_CASES) + 4} cases pass.")


def main():
    if sys.argv[1:] == ["--self-check"]:
        self_check()
    else:
        run()


if __name__ == "__main__":
    main()
