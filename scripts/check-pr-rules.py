#!/usr/bin/env python3
#
#  check-pr-rules.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Fails a pull request that breaks one of the yes-or-no pull request rules.

The rules (Yousef, 2026-11-26), each as one check:
- Template: every section of .github/pull_request_template.md is in the body, and "What changed
  and why", "Merge method" and "Tests" hold text of the author's own. The merge method names
  squash or a merge commit, never a rebase.
- One issue: at most one "Closes", "Fixes" or "Resolves" line, with one reference, and at least
  one closing or "Part of" line.
- CHANGELOG: an added line under "## Unreleased" (or a new version heading, for a release). With
  no CHANGELOG change, nothing under Sources/ or in Package.swift may change, and the body's
  "Docs and CHANGELOG" section says why in a line of its own.
- No attribution: no AI or tool credit in the title, the body, the commit messages or the added
  lines, and no added line citing a private planning issue, a planning repo or a numbered
  decision. Credit means a "Generated", "Written", "Created" or "Made" with, by or using line
  naming an AI tool, a Co-Authored-By trailer naming one, a Claude-Session trailer, any claude.ai
  link (a session, a project or thread, an artifact, a chat or a share), and the hidden project
  credit comment. Nothing is exempt, so the credit lines a tool puts at the top of a body fail
  too (Yousef, 2026-11-28: text posted from the cloud is cleaned after, and this check is the
  net that holds the merge until it is).

Pull requests Dependabot opened from its own dependabot/ branch carry no template and pass.
CodeRabbit's pre-merge checks of the same names explain a failure in words; this script decides.

Usage: check-pr-rules.py             reads PR_TITLE, PR_BODY, PR_AUTHOR, HEAD_REF, BASE_SHA,
                                     HEAD_SHA
       check-pr-rules.py --self-check  runs its own cases and exits
"""

import os
import re
import shutil
import subprocess
import sys

TEMPLATE = ".github/pull_request_template.md"
CHANGELOG = "CHANGELOG.md"
UNRELEASED = "## Unreleased"
# A release heading, such as "## 1.2.0 - 2026-12-01".
# A Markdown heading: up to three spaces, one to six #, then a space or the line's end.
MARKDOWN_HEADING = re.compile(r"^ {0,3}#{1,6}(\s|$)")
VERSION_HEADING = re.compile(r"^## \d+\.\d+\.\d+\b")
WHAT = "What changed and why"
MERGE = "Merge method"
TESTS = "Tests"
DOCS = "Docs and CHANGELOG"
SECTIONS = [WHAT, MERGE, TESTS, DOCS, "Checklist"]
AUTHOR_TEXT_SECTIONS = [WHAT, MERGE, TESTS]
# These files hold the patterns below, so their own lines would always match.
PATTERN_FILES = {"scripts/check-pr-rules.py", "scripts/check-public-text.sh", ".coderabbit.yaml"}

# The tool's name can't run on into a letter or digit, so "cursors" or "Devinder" is plain text.
# An underscore may follow it, as in Markdown emphasis, so "_Made using ChatGPT_" still fails.
AI_TOOLS = r"(claude|anthropic|copilot|codex|cursor|chatgpt|openai|gemini|devin)(?![a-z0-9])"
ATTRIBUTION = [
    re.compile(r"co-authored-by:.*" + AI_TOOLS, re.IGNORECASE),
    re.compile(r"\bclaude-session\s*:", re.IGNORECASE),
    re.compile(
        r"(generated|written|created|made)[*_]*\s+[*_]*(with|by|using)[\W_]*(github[\W_]+)?"
        + AI_TOOLS,
        re.IGNORECASE,
    ),
    # Any claude.ai link: a session, a project or thread, an artifact, a chat or a share. The
    # "Requested by" credit line at the top of a body carries a project link, so it fails here.
    # The host must be claude.ai or one of its subdomains: a bare site link ("https://claude.ai",
    # or the same with a full stop after it) fails, while a longer host such as
    # claude.ai.example.com or one that only ends in the name, such as not-claude.ai, passes. A
    # link's user information is skipped, so the host after an "@" is the one that counts.
    re.compile(
        r"(?<![\w.@-])([\w-]+\.)*claude\.ai/"
        r"|https?://([^\s/@]*@)?([\w-]+\.)*claude\.ai(?![\w@-]|\.\w)",
        re.IGNORECASE,
    ),
    # The hidden credit comment at the top of a generated body.
    re.compile(r"claude-projects-attribution", re.IGNORECASE),
]
PRIVATE_REFS = [
    re.compile(r"planning\s*#\s*\d+", re.IGNORECASE),
    re.compile(r"\b[A-Za-z]+-planning\b"),
    re.compile(r"\bdecisions?\s+\d{3,4}\b", re.IGNORECASE),
]
CLOSING = re.compile(r"^\s*(closes|fixes|resolves)\b", re.IGNORECASE)
PART_OF = re.compile(r"^\s*part of\b", re.IGNORECASE)
# A reference is "#n" or "owner/repo#n"; counting the "#n" part is enough.
REFERENCE = re.compile(r"#\d+")


def strip_comments(text):
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def sections(markdown):
    """Maps each "## " heading to the lines under it, HTML comments removed."""
    found = {}
    current = None
    for line in strip_comments(markdown).splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            found[current] = []
        elif current is not None:
            found[current].append(line)
    return found


def normalized(line):
    return re.sub(r"^\s*- \[[ xX]\]", "- [ ]", line).strip()


def author_lines(body_lines, template_lines):
    template = {normalized(line) for line in template_lines}
    return [line for line in body_lines if line.strip() and normalized(line) not in template]


def template_errors(body, template):
    errors = []
    body_sections = sections(body)
    template_sections = sections(template)
    for name in SECTIONS:
        if name not in body_sections:
            errors.append(f'the "## {name}" section is missing')
    for name in AUTHOR_TEXT_SECTIONS:
        if name in body_sections:
            own = author_lines(body_sections[name], template_sections.get(name, []))
            if not own:
                errors.append(f'"## {name}" holds no text of your own')
    method = " ".join(body_sections.get(MERGE, [])).lower()
    if MERGE in body_sections and method.strip():
        if "rebase" in method:
            errors.append(f'"## {MERGE}" names a rebase merge, which is never used')
        elif "squash" not in method and "merge commit" not in method:
            errors.append(f'"## {MERGE}" names neither squash nor a merge commit')
    return errors


def issue_errors(body):
    errors = []
    lines = strip_comments(body).splitlines()
    closing = [line for line in lines if CLOSING.match(line) and REFERENCE.search(line)]
    part_of = [line for line in lines if PART_OF.match(line) and REFERENCE.search(line)]
    if len(closing) > 1:
        errors.append(f"{len(closing)} closing lines: a pull request closes one issue")
    for line in closing:
        if len(REFERENCE.findall(line)) > 1:
            errors.append(f'"{line.strip()}" closes more than one issue')
    if not closing and not part_of:
        errors.append('no "Closes <owner/repo>#<n>" or "Part of <owner/repo>#<n>" line')
    return errors


def heading_above(lines, number):
    """The line number of the nearest "## " heading at or above a line, or None."""
    return next((n for n in range(number, 0, -1) if lines[n - 1].startswith("## ")), None)


def added_changelog_errors(changelog, added_lines):
    lines = changelog.split("\n")
    new_headings = {number for number in added_lines if VERSION_HEADING.match(lines[number - 1])}
    headings = [
        heading_above(lines, number) for number in added_lines if lines[number - 1].strip()
    ]
    # Only an entry counts, never a heading: editing "## Unreleased" itself adds no entry.
    unreleased = any(
        (heading := heading_above(lines, number)) is not None
        and lines[heading - 1].strip() == UNRELEASED
        for number in added_lines
        if lines[number - 1].strip() and not MARKDOWN_HEADING.match(lines[number - 1])
    )
    errors = [
        f'{CHANGELOG} adds a line under "{lines[heading - 1].strip()}", which is already released'
        for heading in sorted({heading for heading in headings if heading is not None})
        if lines[heading - 1].strip() != UNRELEASED
        and heading not in new_headings
    ]
    if not unreleased and not new_headings:
        errors.append(f'{CHANGELOG} gains no line under "{UNRELEASED}"')
    return errors


def changelog_errors(changelog, added_lines, changed_files, body, template):
    """added_lines are the 1-based numbers of the lines the PR adds to the changelog."""
    if added_lines:
        return added_changelog_errors(changelog, added_lines)
    if CHANGELOG in changed_files:
        return [f"{CHANGELOG} changes but gains no line under \"{UNRELEASED}\""]
    package = [f for f in changed_files if f.startswith("Sources/") or f == "Package.swift"]
    if package:
        return [f"{CHANGELOG} has no entry, and the package changes ({package[0]})"]
    own = author_lines(sections(body).get(DOCS, []), sections(template).get(DOCS, []))
    if not own:
        return [f'{CHANGELOG} has no entry, and "## {DOCS}" doesn\'t say why']
    return []


def credits_a_tool(line):
    return any(pattern.search(line) for pattern in ATTRIBUTION)


def credit_errors(where, text):
    """Each line of the text that credits a tool, or, when the credit is wrapped over several
    lines (as in a Markdown paragraph), the wrapped part."""
    errors = [
        f'{where} credits an AI or tool: "{line.strip()[:80]}"'
        for line in text.splitlines()
        if credits_a_tool(line)
    ]
    if errors:
        return errors
    for pattern in ATTRIBUTION:
        match = pattern.search(text)
        if match:
            wrapped = " ".join(match.group(0).split())
            return [f'{where} credits an AI or tool over several lines: "{wrapped[:80]}"']
    return []


def added_blocks(lines, numbers):
    """The added lines joined into blocks of consecutive lines, so a credit wrapped over two
    added lines is seen whole while lines from separate hunks are never joined. Without
    numbers, the lines count as one block."""
    if not numbers:
        return ["\n".join(lines)] if lines else []
    blocks = []
    block = []
    previous = None
    for number, line in zip(numbers, lines, strict=True):
        if block and number != previous + 1:
            blocks.append("\n".join(block))
            block = []
        block.append(line)
        previous = number
    if block:
        blocks.append("\n".join(block))
    return blocks


def attribution_errors(title, body, commit_messages, added, added_numbers=None):
    """added maps each changed file to its added lines, and added_numbers maps it to their line
    numbers."""
    errors = []
    if credits_a_tool(title):
        errors.append(f'the title credits an AI or tool: "{title.strip()[:80]}"')
    errors += credit_errors("the body", body)
    for message in commit_messages:
        errors += credit_errors("a commit message", message)
    for path, lines in added.items():
        if path in PATTERN_FILES:
            continue
        numbers = (added_numbers or {}).get(path, [])
        if any(credits_a_tool(block) for block in added_blocks(lines, numbers)):
            errors.append(f"{path} adds AI or tool attribution")
        if any(pattern.search(line) for line in lines for pattern in PRIVATE_REFS):
            errors.append(f"{path} adds a private planning or decision reference")
    return sorted(set(errors))


GIT = shutil.which("git") or "git"


def git(*args):
    """Runs git with every path taken literally. The output is decoded without newline
    translation, so a carriage return inside a line stays in that line."""
    # The arguments are this script's own, plus commit ids from the pull request event.
    output = subprocess.run(  # noqa: S603
        [GIT, "--literal-pathspecs", *args], check=True, capture_output=True
    ).stdout
    return output.decode("utf-8", "replace")


def added_lines(patch):
    """The lines a -U0 patch of one file adds, each with its line number in the new file.

    Lines inside a hunk are content, even when they look like a header, so the hunk's own
    counts decide where it ends."""
    added = []
    number = 0
    old_left = new_left = 0
    # Only a line feed ends a patch line; other separators are part of the content.
    for line in patch.split("\n"):
        if old_left == 0 and new_left == 0:
            hunk = re.match(r"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
            if hunk:
                old_left = int(hunk.group(1) or 1)
                number = int(hunk.group(2))
                new_left = int(hunk.group(3) or 1)
            continue
        if line.startswith("+"):
            added.append((number, line[1:]))
            number += 1
            new_left -= 1
        elif line.startswith("-"):
            old_left -= 1
    return added


def added_by_file(base, head, changed):
    """Maps each changed file to its added lines and their numbers. Names come from git's
    NUL-separated list, so no quoted name is lost."""
    added = {}
    added_numbers = {}
    for path in changed:
        patch = git("diff", "--unified=0", "--no-color", f"{base}...{head}", "--", path)
        lines = added_lines(patch)
        if lines:
            added_numbers[path] = [number for number, _ in lines]
            added[path] = [text for _, text in lines]
    return added, added_numbers


def run():
    author = os.environ.get("PR_AUTHOR", "")
    head_ref = os.environ.get("HEAD_REF", "")
    if author == "dependabot[bot]" and head_ref.startswith("dependabot/"):
        print("Opened by Dependabot from its own branch, which carries no template.")
        return 0
    body = os.environ.get("PR_BODY", "")
    base = os.environ["BASE_SHA"]
    head = os.environ["HEAD_SHA"]
    try:
        template = git("show", f"{base}:{TEMPLATE}")
    except subprocess.CalledProcessError:
        with open(TEMPLATE, encoding="utf-8") as file:
            template = file.read()
    changed = [f for f in git("diff", "--name-only", "-z", f"{base}...{head}").split("\0") if f]
    added, numbers = added_by_file(base, head, changed)
    messages = git("log", "--format=%B%x00", f"{base}..{head}").split("\0")
    changelog = git("show", f"{head}:{CHANGELOG}") if CHANGELOG in changed else ""
    checks = {
        "PR template filled in": template_errors(body, template),
        "One issue per PR": issue_errors(body),
        "CHANGELOG under Unreleased": changelog_errors(
            changelog, numbers.get(CHANGELOG, []), changed, body, template
        ),
        "No attribution or private refs": attribution_errors(
            os.environ.get("PR_TITLE", ""), body, messages, added, numbers
        ),
    }
    failed = False
    for name, errors in checks.items():
        if errors:
            failed = True
            for error in errors:
                print(f"::error title={name}::{error}", file=sys.stderr)
        else:
            print(f"{name}: passes")
    if failed:
        print(
            f"Fix the body or the branch, as {TEMPLATE} asks. Editing the body reruns this.",
            file=sys.stderr,
        )
    return 1 if failed else 0


SAMPLE_TEMPLATE = """<!-- Fill in every section. -->

Closes <owner/repo>#<issue>

## What changed and why

<!-- Each change and why. -->

## Merge method

<!-- Squash or merge commit. Never rebase. -->

## Tests

- [ ] Each test names its promise

## Docs and CHANGELOG

- [ ] `CHANGELOG.md` updated under **Unreleased**, or no entry because ...

## Checklist

- [ ] Code follows `CODE_STYLE.md`
"""

FILLED = """Closes owner/repo#12
Part of owner/repo#10

## What changed and why

Adds a check, because nothing held the merge.

## Merge method

Squash, because it has one purpose.

## Tests

- [x] Each test names its promise
The new case pins that an empty body fails.

## Docs and CHANGELOG

- [x] `CHANGELOG.md` updated under **Unreleased**, or no entry because ...

## Checklist

- [x] Code follows `CODE_STYLE.md`
"""

# The private reference samples are built in pieces, so this file doesn't match them itself.
PLANNING_ISSUE = "planning" + " #12"
PLANNING_REPO = "Waypoint-" + "planning"
DECISION = "decision" + " 0012"
# The attribution samples are built in pieces too, so the file adds no attribution itself.
CLAUDE_CODE = "Claude" + " Code"
CLAUDE_AI = "https://claude" + ".ai"
FOOTER = "_Generated " + f"by [{CLAUDE_CODE}]({CLAUDE_AI}/code)_"
ROBOT_FOOTER = "🤖 Generated " + f"with [{CLAUDE_CODE}](https://claude.com/claude-code)"
COPILOT = "Generated " + "by GitHub Copilot"
TRAILER = "Co-Authored-" + "By: Claude <noreply@anthropic.com>"
ANTHROPIC_TRAILER = "Co-authored-" + "by: someone <noreply@anthropic.com>"
SESSION = "Claude-" + "Session: x"
INDENTED_SESSION = "  Claude-" + "Session: x"
SESSION_LINK = f"See {CLAUDE_AI}/code/session_01ABC"
PROJECT_LINK = f"[project thread]({CLAUDE_AI}/code/project/chan_01?thread=cmsg_01)"
REQUESTED_BY = f"_Requested by **Someone** · {PROJECT_LINK}_"
CREDIT_COMMENT = "<!-- claude-projects-" + 'attribution: {"github_login":"someone"} -->'
ARTIFACT_LINK = f"{CLAUDE_AI}/code/artifact/abc"
SHARE_LINK = f"{CLAUDE_AI}/share/abc"
ROOT_LINK = f"See {CLAUDE_AI}."
SUBDOMAIN_LINK = "See https://www.claude" + ".ai"
LONGER_HOST = "See https://claude" + ".ai.example.com/docs and https://notclaude" + ".ai/x"
HYPHENATED_HOST = "See https://not-claude" + ".ai/docs and docs.not-claude" + ".ai/x"
BARE_SUBDOMAIN_PATH = "See www.claude" + ".ai/x"
USER_INFO_LINK = "See https://reader@claude" + ".ai"
OTHER_HOST_USER_INFO = "See https://claude" + ".ai@example.com/docs"
WRITTEN_WITH = "Written " + f"with {CLAUDE_CODE}"
MADE_USING = "Made " + "using ChatGPT"
WRAPPED_CREDIT = "Written " + "with\nClaude Code"
WRAPPED_LINES = WRAPPED_CREDIT.split("\n")
TOOL_AS_WORD_PART = "Made with cursors instead of arrays."
EMPHASIZED_CREDIT = "_Made " + "using ChatGPT_"
EMPHASIZED_TOOL = "Made " + "with _ChatGPT_"
EMPHASIZED_VERB = "**Written** " + f"with {CLAUDE_CODE}"

CHANGELOG_SAMPLE = """# Changelog

## Unreleased

### Added

- New thing.

## 1.0.0 - 2026-11-26

- Old thing.
"""


def template_cases():
    """The template and one-issue cases."""
    return [
        ("a filled-in body passes the template", template_errors(FILLED, SAMPLE_TEMPLATE), 0),
        ("the bare template fails", template_errors(SAMPLE_TEMPLATE, SAMPLE_TEMPLATE), 3),
        (
            "a missing section fails",
            template_errors(FILLED.replace("## Checklist", "## Notes"), SAMPLE_TEMPLATE),
            1,
        ),
        (
            "a rebase merge fails",
            template_errors(FILLED.replace("Squash, because", "Rebase, because"), SAMPLE_TEMPLATE),
            1,
        ),
        ("one Closes and a Part of pass", issue_errors(FILLED), 0),
        ("Part of alone passes", issue_errors("Part of #3\n"), 0),
        ("two closing lines fail", issue_errors("Closes #1\nFixes #2\n"), 1),
        ("one line closing two issues fails", issue_errors("Closes #1, closes #2\n"), 1),
        ("the template's placeholder fails", issue_errors(SAMPLE_TEMPLATE), 1),
    ]


def changelog_entry_cases():
    """The CHANGELOG cases about where an added entry sits."""
    return [
        (
            "a line under Unreleased passes",
            changelog_errors(CHANGELOG_SAMPLE, [7], [CHANGELOG], FILLED, SAMPLE_TEMPLATE),
            0,
        ),
        (
            "a line under a released version fails",
            changelog_errors(CHANGELOG_SAMPLE, [11], [CHANGELOG], FILLED, SAMPLE_TEMPLATE),
            2,
        ),
        (
            "an entry that starts with an issue number passes",
            changelog_errors(
                CHANGELOG_SAMPLE.replace("- New thing.", "#12: New thing."),
                [7],
                [CHANGELOG],
                FILLED,
                SAMPLE_TEMPLATE,
            ),
            0,
        ),
    ]


def changelog_release_heading_cases():
    """The CHANGELOG cases about a new release heading."""
    return [
        (
            "a release heading passes",
            changelog_errors(
                CHANGELOG_SAMPLE.replace("## Unreleased", "## 1.1.0 - 2026-12-01"),
                [3, 7],
                [CHANGELOG],
                FILLED,
                SAMPLE_TEMPLATE,
            ),
            0,
        ),
        (
            "a heading that isn't a version doesn't pass as a release",
            changelog_errors(
                CHANGELOG_SAMPLE.replace("### Added", "## Notes"),
                [5],
                [CHANGELOG],
                FILLED,
                SAMPLE_TEMPLATE,
            ),
            2,
        ),
    ]


def changelog_heading_cases():
    """The CHANGELOG cases about editing a heading."""
    return [
        (
            "an edited Unreleased heading alone fails",
            changelog_errors(CHANGELOG_SAMPLE, [3, 5], [CHANGELOG], FILLED, SAMPLE_TEMPLATE),
            1,
        ),
        (
            "an edited title with an entry passes",
            changelog_errors(CHANGELOG_SAMPLE, [1, 7], [CHANGELOG], FILLED, SAMPLE_TEMPLATE),
            0,
        ),
        (
            "an indented heading alone fails",
            changelog_errors(
                CHANGELOG_SAMPLE.replace("### Added", " ### Added"),
                [5],
                [CHANGELOG],
                FILLED,
                SAMPLE_TEMPLATE,
            ),
            1,
        ),
    ]


def changelog_without_entry_cases():
    """The CHANGELOG cases where the pull request adds no entry."""
    return [
        (
            "no entry with a package change fails",
            changelog_errors("", [], ["Sources/A.swift"], FILLED, SAMPLE_TEMPLATE),
            1,
        ),
        (
            "a changelog that only loses lines fails",
            changelog_errors(CHANGELOG_SAMPLE, [], [CHANGELOG], FILLED, SAMPLE_TEMPLATE),
            1,
        ),
        (
            "no entry and no reason fails",
            changelog_errors("", [], ["scripts/a.sh"], FILLED, SAMPLE_TEMPLATE),
            1,
        ),
        (
            "no entry with a reason passes",
            changelog_errors(
                "",
                [],
                ["scripts/a.sh"],
                FILLED.replace("## Checklist", "No entry: CI only.\n\n## Checklist"),
                SAMPLE_TEMPLATE,
            ),
            0,
        ),
    ]


def body_attribution_cases():
    """Each credit form in the body, and the credit lines at its top."""
    in_body = [
        ("a footer", FOOTER),
        ("a robot footer", ROBOT_FOOTER),
        ("a vendor-first footer", COPILOT),
        ("a session link", SESSION_LINK),
        ("a project link", PROJECT_LINK),
        ("a Requested by credit line", REQUESTED_BY),
        ("the hidden credit comment", CREDIT_COMMENT),
        ("an artifact link", ARTIFACT_LINK),
        ("a share link", SHARE_LINK),
        ("a site root link", ROOT_LINK),
        ("a subdomain link", SUBDOMAIN_LINK),
        ("a written-with line", WRITTEN_WITH),
        ("a made-using line", MADE_USING),
    ]
    cases = [
        ("a plain body passes", attribution_errors("Add a check", FILLED, ["Add a check"], {}), 0),
    ]
    cases += [
        (
            f"{name} in the body fails",
            attribution_errors("", FILLED + f"\n{line}\n", [], {}),
            1,
        )
        for name, line in in_body
    ]
    cases += [
        (
            "the credit lines at the top of a body fail",
            attribution_errors("", f"{CREDIT_COMMENT}\n{REQUESTED_BY}\n\n{FILLED}", [], {}),
            2,
        ),
    ]
    return cases


def title_and_host_cases():
    """Credit in the title, and which host names count as the site."""
    return [
        ("a credit in the title fails", attribution_errors(WRITTEN_WITH, "", [], {}), 1),
        ("a link in the title fails", attribution_errors(SESSION_LINK, "", [], {}), 1),
        ("a longer host name passes", attribution_errors(LONGER_HOST, LONGER_HOST, [], {}), 0),
        (
            "a credit wrapped over two lines fails",
            attribution_errors("", WRAPPED_CREDIT, [], {}),
            1,
        ),
        (
            "a credit wrapped in a commit fails",
            attribution_errors("", "", [f"Fix\n\n{WRAPPED_CREDIT}"], {}),
            1,
        ),
        (
            "a tool name inside a longer word passes",
            attribution_errors(TOOL_AS_WORD_PART, TOOL_AS_WORD_PART, [TOOL_AS_WORD_PART], {}),
            0,
        ),
        ("a credit in emphasis fails", attribution_errors(EMPHASIZED_CREDIT, "", [], {}), 1),
        ("a tool name in emphasis fails", attribution_errors(EMPHASIZED_TOOL, "", [], {}), 1),
        ("a verb in emphasis fails", attribution_errors(EMPHASIZED_VERB, "", [], {}), 1),
        ("a hyphenated host name passes", attribution_errors(HYPHENATED_HOST, "", [], {}), 0),
        ("a subdomain path fails", attribution_errors(BARE_SUBDOMAIN_PATH, "", [], {}), 1),
        ("a link with user information fails", attribution_errors(USER_INFO_LINK, "", [], {}), 1),
        (
            "user information naming the site passes",
            attribution_errors(OTHER_HOST_USER_INFO, "", [], {}),
            0,
        ),
    ]


def commit_attribution_cases():
    """Credit in commit messages."""
    return [
        (
            "a co-author trailer fails",
            attribution_errors("", "", [f"Fix\n\n{TRAILER}"], {}),
            1,
        ),
        (
            "an anthropic co-author fails",
            attribution_errors("", "", [f"Fix\n\n{ANTHROPIC_TRAILER}"], {}),
            1,
        ),
        ("a session line fails", attribution_errors("", "", [f"Fix\n\n{SESSION}"], {}), 1),
        (
            "an indented session line fails",
            attribution_errors("", "", [f"Fix\n\n{INDENTED_SESSION}"], {}),
            1,
        ),
        (
            "a link in a commit fails",
            attribution_errors("", "", [f"Fix\n\n{SESSION_LINK}"], {}),
            1,
        ),
    ]


def added_line_cases():
    """Credit in the lines a pull request adds."""
    return [
        (
            "a footer in a file fails",
            attribution_errors("", "", [], {"README.md": [FOOTER]}),
            1,
        ),
        (
            "a project link in a file fails",
            attribution_errors("", "", [], {"docs/notes.md": [PROJECT_LINK]}),
            1,
        ),
        (
            "a credit wrapped over two added lines fails",
            attribution_errors(
                "", "", [], {"README.md": WRAPPED_LINES}, {"README.md": [4, 5]}
            ),
            1,
        ),
        (
            "a credit split across two hunks passes",
            attribution_errors(
                "", "", [], {"README.md": WRAPPED_LINES}, {"README.md": [4, 9]}
            ),
            0,
        ),
        (
            "this file's own patterns pass",
            attribution_errors("", "", [], {"scripts/check-pr-rules.py": [FOOTER]}),
            0,
        ),
    ]


def private_reference_cases():
    """Private planning references in added lines, and plain text that passes."""
    return [
        (
            "a planning reference in a file fails",
            attribution_errors("", "", [], {"README.md": [f"See {PLANNING_ISSUE}."]}),
            1,
        ),
        (
            "a planning repo name in a file fails",
            attribution_errors("", "", [], {"a.swift": [f"// in {PLANNING_REPO}"]}),
            1,
        ),
        (
            "a numbered decision in a file fails",
            attribution_errors("", "", [], {"a.md": [f"As {DECISION} says."]}),
            1,
        ),
        (
            "plain text passes",
            attribution_errors(
                "Plan the release",
                "",
                ["Add a plan"],
                {"a.md": ["Plan the route, then decide.", "Made with care by hand."]},
            ),
            0,
        ),
    ]


def patch_cases():
    """How a patch's added lines are read."""
    cases = []
    patch = "--- a/n.md\n+++ b/n.md\n@@ -0,0 +1,2 @@\n+++ looks like a header\n+second\n"
    for name, separator in (("a line separator", "\u2028"), ("a carriage return", "\r")):
        odd = f"--- a/n.md\n+++ b/n.md\n@@ -0,0 +1,2 @@\n+one{separator}two\n+filler\n"
        cases.append(
            (
                f"an added line holding {name} stays one line",
                [] if added_lines(odd) == [(1, f"one{separator}two"), (2, "filler")] else ["x"],
                0,
            )
        )
    cases.append(
        (
            "an added line that looks like a header is still content",
            [] if added_lines(patch) == [(1, "++ looks like a header"), (2, "second")] else ["x"],
            0,
        )
    )
    return cases


def self_check_cases():
    """Each case is (name, errors found, errors expected): the table the self-check runs."""
    return (
        template_cases()
        + changelog_entry_cases()
        + changelog_release_heading_cases()
        + changelog_heading_cases()
        + changelog_without_entry_cases()
        + body_attribution_cases()
        + title_and_host_cases()
        + commit_attribution_cases()
        + added_line_cases()
        + private_reference_cases()
        + patch_cases()
    )


def self_check():
    failed = 0
    cases = self_check_cases()
    for name, errors, expected in cases:
        if len(errors) != expected:
            failed += 1
            print(
                f"self-check failed: {name}: expected {expected} errors, got {errors}",
                file=sys.stderr,
            )
    if failed:
        return 1
    print(f"self-check: {len(cases)} cases pass")
    return 0


def main():
    return self_check() if "--self-check" in sys.argv else run()


if __name__ == "__main__":
    sys.exit(main())
