#!/usr/bin/env python3
#
#  publish-github-text.py
#  Understudy
#
#  Created by Yousef Mohamed youseef.elserwey@gmail.com.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Publishes the GitHub text a pushed text commit carries, as Yousef (2026-11-28).

Text written to GitHub from the cloud gets a tool credit line added on the way, and GitHub keeps
that first revision in the edit history. Commits pushed with git are untouched. So cloud work
writes its pull request, issue or comment text into files, commits them on top of its work and
pushes; this script then publishes the text with Yousef's own token, and the first revision is
the clean one. It is the one home for these rules:

- The text commit is the pushed commit. It must be Verified and change only files under
  .github/text-to-publish/. A pushed commit that touches none of them is not a text commit, and
  nothing happens.
- Each file there is one message: "key: value" lines, a line holding only "---", then the
  Markdown text. Files are published in name order, so 1-issue.md goes before
  2-pull-request.md. The kinds and their keys are in KINDS below.
- A pull request's head branch is moved to the text commit's parent, the last work commit:
  created there, or fast-forwarded to it. It is never moved backwards or sideways, and isn't
  moved at all when it already holds that commit, so a text-only update is a text commit made on
  top of the head branch's latest commit. The head can't be the pushed branch. Every commit it
  gains must be Verified and none may touch .github/text-to-publish/, so the text files never
  reach a pull request. The pull request for that head is opened, or its title and text updated.
- When every message is published, the pushed branch is moved back to the work commit, while it
  is still at the text commit, so the text commit is gone and the work stays. A branch pushed to
  since is left alone, and so is a branch after a failure. The pushing side drops the text
  commit from its own copy (git reset --hard HEAD~1) right after the push, so its next push is a
  fast-forward again.
- The run summary links each published item as it goes.

The same file is in every repo. Python 3 and git, nothing else.

Usage: publish-github-text.py               reads UNDERSTUDY_TEXT_PUBLISHER_TOKEN,
                                            GITHUB_REPOSITORY, TEXT_COMMIT (the pushed commit)
                                            and PUSHED_BRANCH (the pushed branch)
       publish-github-text.py --self-check  runs its own cases and exits
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

TEXT_FOLDER = ".github/text-to-publish/"
SEPARATOR = "---"
GIT = shutil.which("git") or "git"

# Each kind's keys: True marks the ones a message must have.
KINDS = {
    # Opens the pull request from head into base, or updates the open one's title and text.
    # draft applies when it is opened. assignees and reviewers are comma-separated logins.
    "pull-request": {
        "title": True, "head": True, "base": False, "draft": False,
        "assignees": False, "reviewers": False,
    },
    # Opens an issue, or, with number, updates that issue's title and text.
    "issue": {"title": True, "number": False, "labels": False, "assignees": False},
    # A comment on the issue or pull request number "on". With reply-to, a reply in that review
    # comment's thread instead; with edit, that comment's text is replaced.
    "comment": {"on": True, "reply-to": False, "edit": False},
}
NUMBER_KEYS = {"number", "on", "reply-to", "edit"}
BRANCH_NAME = re.compile(r"^[A-Za-z0-9._/-]+$")


class PublishError(Exception):
    """A message or a commit that can't be posted, with a reason a person can act on."""


def parse_message(path, text):
    """Reads one text file into (fields, body). Raises PublishError naming the file."""
    lines = text.splitlines()
    if SEPARATOR not in (line.strip() for line in lines):
        raise PublishError(f'{path} has no line holding only "{SEPARATOR}" before its text')
    fields = {}
    position = 0
    for position, line in enumerate(lines):
        if line.strip() == SEPARATOR:
            break
        if not line.strip():
            continue
        key, colon, value = line.partition(":")
        key = key.strip().lower()
        if not colon or not key:
            raise PublishError(f'{path} line {position + 1} is not "key: value": {line!r}')
        if key in fields:
            raise PublishError(f"{path} sets {key} twice")
        fields[key] = value.strip()
    body = "\n".join(lines[position + 1:]).strip("\n") + "\n"
    kind = fields.pop("kind", "")
    if kind not in KINDS:
        raise PublishError(f"{path} has kind {kind!r}; it must be one of {', '.join(KINDS)}")
    allowed = KINDS[kind]
    unknown = sorted(set(fields) - set(allowed))
    if unknown:
        raise PublishError(f"{path} has keys a {kind} doesn't take: {', '.join(unknown)}")
    missing = [key for key, required in allowed.items() if required and not fields.get(key)]
    if missing:
        raise PublishError(f"{path} is a {kind} without {', '.join(missing)}")
    for key in NUMBER_KEYS & set(fields):
        if not fields[key].isdigit():
            raise PublishError(f"{path} {key} must be a number, not {fields[key]!r}")
    if fields.get("draft", "true") not in ("true", "false"):
        raise PublishError(f"{path} draft must be true or false")
    for key in ("head", "base"):
        if key in fields and not BRANCH_NAME.match(fields[key]):
            raise PublishError(f"{path} {key} is not a branch name: {fields[key]!r}")
    if kind == "comment" and "reply-to" in fields and "edit" in fields:
        raise PublishError(f"{path} sets both reply-to and edit; a comment does one")
    if not body.strip():
        raise PublishError(f"{path} has no text after {SEPARATOR}")
    return kind, fields, body


def logins(value):
    return [login.strip() for login in value.split(",") if login.strip()]


def text_commit_errors(changed_paths):
    """Why the pushed commit can't be a text commit, or None when it isn't one at all."""
    text_paths = [path for path in changed_paths if path.startswith(TEXT_FOLDER)]
    if not text_paths:
        return None
    others = [path for path in changed_paths if not path.startswith(TEXT_FOLDER)]
    if others:
        return [f"the text commit changes files outside {TEXT_FOLDER}: {', '.join(others)}. "
                "Commit the work first and the text files in a commit of their own on top."]
    return []


def head_move(head_commit, work_commit, is_ancestor):
    """What to do with the pull request's head branch: "create", "keep" or "fast-forward".
    head_commit is None when the branch doesn't exist; is_ancestor(older, newer) asks git."""
    if head_commit is None:
        return "create"
    if head_commit == work_commit or is_ancestor(work_commit, head_commit):
        return "keep"
    if is_ancestor(head_commit, work_commit):
        return "fast-forward"
    raise PublishError(
        f"the head branch is at {head_commit}, which the work commit {work_commit} doesn't "
        "build on. Rebase the work on the head branch, or push the head branch yourself first."
    )


def gained_commit_errors(commits, changed_paths):
    """Errors for the commits a head branch would gain: commits is a list of (sha, verified)."""
    errors = [f"commit {sha} is not Verified" for sha, verified in commits if not verified]
    leaked = [path for path in changed_paths if path.startswith(TEXT_FOLDER)]
    if leaked:
        errors.append(f"the work commits touch {TEXT_FOLDER} ({', '.join(leaked)}), which "
                      "must never reach a pull request")
    return errors


def git(*arguments, environment=None):
    # The arguments are this script's own, commit ids from the push event and branch names
    # checked against BRANCH_NAME.
    completed = subprocess.run(  # noqa: S603
        [GIT, "--literal-pathspecs", *arguments],
        check=True, capture_output=True, env=environment,
    )
    return completed.stdout.decode("utf-8", "replace")


class GitHub:
    def __init__(self, token, repository):
        self.token = token
        self.repository = repository
        self.owner = repository.split("/")[0]
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

    def request(self, method, path, payload=None, allow_missing=False):
        url = f"{self.base}{path}"
        if not url.startswith("https://"):
            raise ValueError(f"Refusing a URL that isn't HTTPS: {url}")
        data = json.dumps(payload).encode() if payload is not None else None
        # Checked above: only HTTPS, to GitHub's API.
        request = urllib.request.Request(url, data=data, method=method, headers={  # noqa: S310
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
                text = response.read()
        except urllib.error.HTTPError as error:
            if allow_missing and error.code == 404:
                return None
            detail = error.read().decode("utf-8", "replace")[:500]
            raise PublishError(f"GitHub refused {method} {path}: {error.code} {detail}") from error
        return json.loads(text) if text else {}

    def verified(self, sha):
        commit = self.request("GET", f"/commits/{sha}")
        return bool(commit["commit"]["verification"]["verified"])

    def branch_commit(self, name):
        ref = self.request("GET", f"/git/ref/heads/{name}", allow_missing=True)
        return ref["object"]["sha"] if ref else None

    def fetch(self, *refs):
        git("fetch", "--quiet", "--no-tags", self.remote, *refs,
            environment=self.git_environment)

    def push(self, lease, refspec):
        git("push", "--porcelain", lease, self.remote, refspec, environment=self.git_environment)


def is_ancestor(older, newer):
    result = subprocess.run(  # noqa: S603
        [GIT, "merge-base", "--is-ancestor", older, newer], check=False, capture_output=True,
    )
    return result.returncode == 0


class Summary:
    """The run summary, written a line at a time, so what was posted is there even if a run
    stops part way."""

    def __init__(self):
        path = os.environ.get("GITHUB_STEP_SUMMARY")
        self.path = Path(path) if path else None

    def write(self, text):
        print(text)
        if self.path:
            with self.path.open("a", encoding="utf-8") as summary:
                summary.write(text + "\n")


def move_head(github, fields, work_commit):
    head = fields["head"]
    base = fields.get("base", "main")
    head_commit = github.branch_commit(head)
    github.fetch(f"+refs/heads/{base}:refs/remotes/publisher/{base}",
                 *([f"+refs/heads/{head}:refs/remotes/publisher/{head}"] if head_commit else []))
    action = head_move(head_commit, work_commit, is_ancestor)
    if action == "keep":
        return action
    since = head_commit or f"refs/remotes/publisher/{base}"
    shas = [sha for sha in git("rev-list", f"{since}..{work_commit}").split() if sha]
    paths = [path for path in git("diff", "--name-only", "-z", f"{since}...{work_commit}")
             .split("\0") if path]
    errors = gained_commit_errors([(sha, github.verified(sha)) for sha in shas], paths)
    if errors:
        raise PublishError(f"can't move {head}: " + "; ".join(errors))
    # Without --force git refuses anything but a create or a fast-forward, and the lease makes
    # a branch pushed to since this run looked at it fail instead of being moved.
    lease = f"--force-with-lease=refs/heads/{head}:{head_commit or ''}"
    github.push(lease, f"{work_commit}:refs/heads/{head}")
    return action


def post_pull_request(github, fields, body, work_commit):
    action = move_head(github, fields, work_commit)
    head = fields["head"]
    pulls = github.request("GET", f"/pulls?state=open&head={github.owner}:{head}")
    if pulls:
        number = pulls[0]["number"]
        pull = github.request("PATCH", f"/pulls/{number}", {"title": fields["title"], "body": body})
        verb = "Updated"
    else:
        pull = github.request("POST", "/pulls", {
            "title": fields["title"], "body": body, "head": head,
            "base": fields.get("base", "main"), "draft": fields.get("draft", "true") == "true",
        })
        number = pull["number"]
        verb = "Opened"
    warnings = []
    if fields.get("assignees"):
        github.request("POST", f"/issues/{number}/assignees",
                       {"assignees": logins(fields["assignees"])})
    reviewers = [login for login in logins(fields.get("reviewers", ""))
                 if login.lower() != pull["user"]["login"].lower()]
    if len(reviewers) < len(logins(fields.get("reviewers", ""))):
        warnings.append("GitHub doesn't let a pull request's author be asked to review it, so "
                        "that reviewer was left out")
    if reviewers:
        github.request("POST", f"/pulls/{number}/requested_reviewers", {"reviewers": reviewers})
    head_note = {"keep": "head unchanged", "create": f"made {head}",
                 "fast-forward": f"moved {head}"}[action]
    return f"{verb} pull request [#{number}]({pull['html_url']}) ({head_note})", warnings


def post_issue(github, fields, body):
    payload = {"title": fields["title"], "body": body}
    if fields.get("labels"):
        payload["labels"] = logins(fields["labels"])
    if fields.get("assignees"):
        payload["assignees"] = logins(fields["assignees"])
    if fields.get("number"):
        issue = github.request("PATCH", f"/issues/{fields['number']}", payload)
        return f"Updated issue [#{issue['number']}]({issue['html_url']})", []
    issue = github.request("POST", "/issues", payload)
    return f"Opened issue [#{issue['number']}]({issue['html_url']})", []


def post_comment(github, fields, body):
    number = fields["on"]
    if fields.get("reply-to"):
        comment = github.request(
            "POST", f"/pulls/{number}/comments/{fields['reply-to']}/replies", {"body": body})
        return f"Replied on #{number}: {comment['html_url']}", []
    if fields.get("edit"):
        comment = github.request("PATCH", f"/issues/comments/{fields['edit']}", {"body": body})
        return f"Edited a comment on #{number}: {comment['html_url']}", []
    comment = github.request("POST", f"/issues/{number}/comments", {"body": body})
    return f"Commented on #{number}: {comment['html_url']}", []


def run():
    token = os.environ.get("UNDERSTUDY_TEXT_PUBLISHER_TOKEN", "")
    text_commit = os.environ["TEXT_COMMIT"]
    branch = os.environ["PUSHED_BRANCH"]
    changed = [path for path in git("diff-tree", "--no-commit-id", "--name-only", "-r", "-z",
                                    "--root", text_commit).split("\0") if path]
    errors = text_commit_errors(changed)
    if errors is None:
        print(f"{text_commit} changes no file under {TEXT_FOLDER}, so it isn't a text commit.")
        return 0
    if errors:
        raise PublishError(errors[0])
    if not token:
        raise PublishError("the UNDERSTUDY_TEXT_PUBLISHER_TOKEN secret is missing. Yousef "
                          "makes it; see the workflow file's comment.")
    github = GitHub(token, os.environ["GITHUB_REPOSITORY"])
    if not github.verified(text_commit):
        raise PublishError(f"the text commit {text_commit} is not Verified")
    work_commit = git("rev-parse", f"{text_commit}^").strip()
    # Files the commit adds or changes; one it deletes has nothing to post.
    present = sorted(path for path in git("diff-tree", "--no-commit-id", "--name-only", "-r",
                                          "-z", "--root", "--diff-filter=AM", text_commit)
                     .split("\0") if path)
    messages = [parse_message(path, git("show", f"{text_commit}:{path}"))
                for path in present]
    for path, (kind, fields, body) in zip(present, messages, strict=True):
        if kind == "pull-request" and fields["head"] == branch:
            raise PublishError(f"{path} names the pushed branch as its head; push the text "
                              "commit to another branch, such as the cloud work's claude/ one")
    summary = Summary()
    summary.write(f"### Text commit {text_commit[:12]} on {branch}\n")
    for path, (kind, fields, body) in zip(present, messages, strict=True):
        if kind == "pull-request":
            line, warnings = post_pull_request(github, fields, body, work_commit)
        elif kind == "issue":
            line, warnings = post_issue(github, fields, body)
        else:
            line, warnings = post_comment(github, fields, body)
        summary.write(f"- {path}: {line}")
        for warning in warnings:
            print(f"::warning::{path}: {warning}")
    try:
        github.push(f"--force-with-lease=refs/heads/{branch}:{text_commit}",
                    f"+{work_commit}:refs/heads/{branch}")
        summary.write(f"\nMoved {branch} back to the work commit {work_commit[:12]}.")
    except subprocess.CalledProcessError:
        summary.write(f"\nLeft {branch} alone: it was pushed to after the text commit.")
    return 0


PULL_REQUEST_SAMPLE = """kind: pull-request
title: Open pull requests from a workflow
head: ci/111-post-github-text-from-a-workflow
draft: false
reviewers: SomeReviewer

---
Closes #111

## What changed and why

The text.
"""


def parse_cases():
    """How text files are read."""
    def errors_of(text, path=".github/text-to-publish/message.md"):
        try:
            parse_message(path, text)
        except PublishError as error:
            return [str(error)]
        return []

    kind, fields, body = parse_message("sample", PULL_REQUEST_SAMPLE)
    read_right = (kind == "pull-request" and fields["head"].startswith("ci/111")
                  and fields["draft"] == "false" and body.startswith("Closes #111\n")
                  and body.endswith("The text.\n") and "---" not in body)
    ruled_body = parse_message(
        "ruled", "kind: issue\ntitle: Ruled\n---\nabove\n\n---\nbelow\n")[2]
    return [
        ("a pull request message is read into its kind, keys and text", [] if read_right
         else ["read wrong"], 0),
        ("a later --- line is part of the text", [] if ruled_body == "above\n\n---\nbelow\n"
         else ["cut"], 0),
        ("a message without --- fails", errors_of("kind: issue\ntitle: Only\n"), 1),
        ("an unknown kind fails", errors_of("kind: discussion\ntitle: Talk\n---\nText\n"), 1),
        ("a missing kind fails", errors_of("title: Talk\n---\nText\n"), 1),
        ("a pull request without head fails",
         errors_of("kind: pull-request\ntitle: Work\n---\nText\n"), 1),
        ("a key the kind doesn't take fails",
         errors_of("kind: issue\ntitle: Work\nhead: ci/1-work\n---\nText\n"), 1),
        ("a key set twice fails", errors_of("kind: issue\ntitle: One\ntitle: Two\n---\nText\n"), 1),
        ("a line that isn't key: value fails", errors_of("kind: issue\ntitle Work\n---\nText\n"),
         1),
        ("a comment number that isn't a number fails",
         errors_of("kind: comment\non: #12\n---\nText\n"), 1),
        ("a draft that isn't true or false fails",
         errors_of("kind: pull-request\ntitle: Work\nhead: ci/1-work\ndraft: yes\n---\nText\n"),
         1),
        ("a head with spaces fails",
         errors_of("kind: pull-request\ntitle: Work\nhead: ci/1 work\n---\nText\n"), 1),
        ("a comment that both replies and edits fails",
         errors_of("kind: comment\non: 3\nreply-to: 4\nedit: 5\n---\nText\n"), 1),
        ("a message with no text fails", errors_of("kind: issue\ntitle: Work\n---\n\n"), 1),
        ("a comment with on and text passes", errors_of("kind: comment\non: 12\n---\nThanks.\n"),
         0),
        ("keys are read whatever their case", errors_of("Kind: issue\nTitle: Work\n---\nText\n"),
         0),
    ]


def commit_cases():
    """Which pushed commits are text commits, and what a head branch may gain."""
    no_text = text_commit_errors(["Sources/Clock.swift"])
    return [
        ("a commit with no text file is not a text commit",
         [] if no_text is None else ["treated as text"], 0),
        ("a text-only commit passes", text_commit_errors([".github/text-to-publish/pr.md"]), 0),
        ("a text commit that also changes work fails",
         text_commit_errors([".github/text-to-publish/pr.md", "README.md"]), 1),
        ("a file merely named text-to-publish elsewhere is not a text file",
         [] if text_commit_errors(["docs/text-to-publish/pr.md"]) is None
         else ["treated as text"], 0),
        ("verified work commits pass", gained_commit_errors([("abc1", True)], ["README.md"]), 0),
        ("an unverified work commit fails",
         gained_commit_errors([("abc1", True), ("abc2", False)], ["README.md"]), 1),
        ("work that touches the text folder fails",
         gained_commit_errors([("abc1", True)], [".github/text-to-publish/pr.md"]), 1),
    ]


def head_cases():
    """How a pull request's head branch is moved. History: base <- work1 <- work2."""
    order = ["base", "work1", "work2"]

    def ancestor(older, newer):
        return older in order and newer in order and order.index(older) <= order.index(newer)

    def move(head_commit, work_commit):
        try:
            return head_move(head_commit, work_commit, ancestor)
        except PublishError:
            return "refused"

    return [
        (f"head at {head} with work at {work} is {expected}",
         [] if move(head, work) == expected else [move(head, work)], 0)
        for head, work, expected in (
            (None, "work2", "create"),
            ("work1", "work2", "fast-forward"),
            ("work2", "work2", "keep"),
            ("work2", "base", "keep"),
            ("sideways", "work2", "refused"),
        )
    ]


def self_check_cases():
    """Each case is (name, errors found, errors expected): the table the self-check runs."""
    return parse_cases() + commit_cases() + head_cases()


def self_check():
    failed = 0
    cases = self_check_cases()
    for name, errors, expected in cases:
        if len(errors) != expected:
            failed += 1
            print(f"self-check failed: {name}: expected {expected} errors, got {errors}",
                  file=sys.stderr)
    if failed:
        return 1
    print(f"self-check: {len(cases)} cases pass")
    return 0


def main():
    if "--self-check" in sys.argv:
        return self_check()
    try:
        return run()
    except PublishError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
