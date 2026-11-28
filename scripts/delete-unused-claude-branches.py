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
never removes the claude/ branch, since it is no pull request's head, so this script does:

- It looks only at branches under claude/.
- It keeps a branch whose head commit is the head commit of an open pull request, or that is an
  open pull request's head branch by name. The commit is what links the two, because the branch
  the pull request is opened from has another name.
- It keeps a branch whose head commit is less than MINIMUM_AGE_HOURS old, so work that is still going
  isn't hit between its push and its fast-forward.
- It deletes the rest, and prints each deleted branch with its commit, so one can be put back
  from that commit.

The same file is in every repo. Python 3, nothing else.

Usage: delete-unused-claude-branches.py               reads GITHUB_TOKEN, GITHUB_REPOSITORY,
                                                      DRY_RUN ("true" lists and deletes nothing)
       delete-unused-claude-branches.py --self-check  runs its own cases and exits
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

PREFIX = "claude/"
MINIMUM_AGE_HOURS = 24
MINIMUM_AGE = timedelta(hours=MINIMUM_AGE_HOURS)
NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')


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


class GitHub:
    def __init__(self, token, repository):
        self.token = token
        api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
        self.base = f"{api}/repos/{repository}"

    def request(self, url, method="GET"):
        request = urllib.request.Request(url, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        })
        # The URL is GitHub's API, from GITHUB_API_URL or a Link header GitHub sent.
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            body = response.read()
            return (json.loads(body) if body else None), response.headers.get("Link", "")

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

    def delete_branch(self, name):
        self.request(f"{self.base}/git/refs/heads/{urllib.parse.quote(name, safe='/')}", "DELETE")


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def run():
    token = os.environ["GITHUB_TOKEN"]
    repository = os.environ["GITHUB_REPOSITORY"]
    dry_run = os.environ.get("DRY_RUN", "false") == "true"
    github = GitHub(token, repository)
    branches = github.claude_branches()
    chosen = deletable(branches, github.open_pulls(), github.committed_at,
                       datetime.now(timezone.utc))
    print(f"{len(branches)} {PREFIX} branches, {len(chosen)} that no open pull request uses and "
          f"older than {MINIMUM_AGE_HOURS} hours.")
    lines = ["| Branch | Commit |", "| --- | --- |"]
    for name in chosen:
        if not dry_run:
            github.delete_branch(name)
        print(f"{'Would delete' if dry_run else 'Deleted'} {name} at {branches[name]}")
        lines.append(f"| `{name}` | `{branches[name]}` |")
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        heading = "Would delete (dry run)" if dry_run else "Deleted"
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write(f"### {heading}: {len(chosen)} of {len(branches)} {PREFIX} branches\n\n")
            if chosen:
                summary.write("\n".join(lines) + "\n")


NOW = datetime(2026, 11, 28, 12, 0, tzinfo=timezone.utc)
OLD = NOW - timedelta(days=3)
COMMIT_TIMES = {"old1": OLD, "old2": OLD, "old3": OLD, "fresh": NOW - timedelta(hours=2),
                "edge": NOW - MINIMUM_AGE}
SELF_CHECK_CASES = [
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


def self_check():
    failures = 0
    for branches, open_pulls, expected, promise in SELF_CHECK_CASES:
        found = deletable(branches, open_pulls, COMMIT_TIMES.__getitem__, NOW)
        if found != expected:
            failures += 1
            print(f"FAIL: {promise}: expected {expected}, got {found}")
    assert parse_time("2026-11-28T12:00:00Z") == NOW, "GitHub's Z times are read as UTC"
    if failures:
        sys.exit(1)
    print(f"All {len(SELF_CHECK_CASES)} cases pass.")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        self_check()
    else:
        run()
