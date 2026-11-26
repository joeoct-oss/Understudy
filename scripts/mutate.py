#!/usr/bin/env python3
#
#  mutate.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Mutation testing: changes one thing at a time in Sources/, runs the tests that cover it, and
records whether a test noticed. A mutant that no test notices "survived": a break the tests would
let through. Python 3, nothing else.

Each mutant is one of these changes on one line of code (comments and string literals are left
alone): `==` and `!=` swapped, `<` and `<=` or `>` and `>=` swapped, `&&` and `||` swapped,
`true` and `false` swapped, `+ 1` and `- 1` swapped, a `!` removed, or a statement removed. The
package is built with the tests, and every test must pass before the first change; a mutant that
doesn't build counts as neither killed nor survived. The tests of the feature the file belongs to
run first; a mutant they miss runs against every test before it is recorded as survived, so a
survivor is one the whole suite misses. A run longer than the time limit counts as killed, since a
test that hangs noticed the change.

Results go to mutants.tsv at the package's root, which git ignores, one line per mutant, as they
come; a run reads it first and skips every mutant already in it whose line is unchanged, so a long
run can stop and go on later. Only files under Sources/ are mutated, and only when git has every
change to them.

Usage: scripts/mutate.py [--list] [--timeout <seconds>] [<file or folder under Sources/>...]
"""

import argparse
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
INLINE_COMMENT = re.compile(r"/\*.*?\*/")
SWAPS = [
    (re.compile(r"(?<=\s)==(?=\s)"), "!="),
    (re.compile(r"(?<=\s)!=(?=\s)"), "=="),
    (re.compile(r"(?<=\s)<=(?=\s)"), "<"),
    (re.compile(r"(?<=\s)<(?=\s)"), "<="),
    (re.compile(r"(?<=\s)>=(?=\s)"), ">"),
    (re.compile(r"(?<=\s)>(?=\s)"), ">="),
    (re.compile(r"(?<=\s)&&(?=\s)"), "||"),
    (re.compile(r"(?<=\s)\|\|(?=\s)"), "&&"),
    (re.compile(r"\btrue\b"), "false"),
    (re.compile(r"\bfalse\b"), "true"),
    (re.compile(r"(?<=\s)\+ 1\b"), "- 1"),
    (re.compile(r"(?<=\s)- 1\b"), "+ 1"),
    (re.compile(r"(?<=[\s(])!(?=[\w(.$])"), ""),
]
# A line that is a whole statement on its own, which removing leaves the code still building often
# enough to be worth trying: a call, an assignment or a mutation, never a declaration or control.
STATEMENT = re.compile(r"^\s*(?:self\.)?[a-z_][\w.]*(?:\(|\s*[+-]?=\s)")
NOT_STATEMENT = re.compile(
    r"^\s*(let|var|return|guard|if|else|for|while|switch|case|default|func|init|throw|try|await|"
    r"defer|do|catch|break|continue|fallthrough|super\.init|self\.init)\b"
)
# Which tests each part of Sources/ answers to first, by path prefix: the most specific wins.
FEATURE_TESTS = [
    ("Sources/Understudy/Clock/", ["--filter", "TestClockTests"]),
    ("Sources/Understudy/", ["--filter", "UnderstudyTests", "--skip", "TestClockTests"]),
    ("Sources/UnderstudyMacros/", ["--filter", "UnderstudyMacrosTests"]),
    ("Sources/UnderstudySamplesMacros/", ["--filter", "UnderstudySamplesMacrosTests"]),
    ("Sources/UnderstudySamples/", ["--filter", "UnderstudySamplesTests"]),
]


def code_lines(text):
    """Every line outside comments and multi-line strings, as (index, line with strings blanked)."""
    in_block = in_multiline = False
    for index, line in enumerate(text.split("\n")):
        stripped = line.strip()
        if in_block:
            in_block = "*/" not in line
            continue
        if line.count('"""') % 2 == 1:
            in_multiline = not in_multiline
            continue
        if in_multiline or not stripped or stripped.startswith(("//", "#", "@")):
            continue
        if stripped.startswith("/*"):
            in_block = "*/" not in line
            continue
        code = STRING.sub(lambda match: '"' + " " * (len(match.group()) - 2) + '"', line)
        code = INLINE_COMMENT.sub(lambda match: " " * len(match.group()), code).split("//")[0]
        if "/*" in code:
            code, in_block = code[:code.index("/*")], True
        yield index, code


def balanced(code):
    """Whether a line closes every bracket it opens, so removing it alone can still build."""
    return all(code.count(left) == code.count(right) for left, right in ("{}", "()", "[]"))


def mutants(path):
    """Every mutant of one file, as (line index, column, description, mutated line)."""
    lines = path.read_text().split("\n")
    for index, code in code_lines("\n".join(lines)):
        original = lines[index]
        for pattern, replacement in SWAPS:
            for match in pattern.finditer(code):
                mutated = original[:match.start()] + replacement + original[match.end():]
                yield index, match.start(), f"{match.group()} -> {replacement or 'nothing'}", mutated
        if STATEMENT.match(code) and not NOT_STATEMENT.match(code) and balanced(code):
            yield index, 0, "statement removed", ""


def run(arguments, timeout):
    """Whether the command passed, failed or ran out of time. A command that runs out of time is
    stopped with every process it started, such as the test runner `swift test` starts, so a
    mutant that hangs leaves nothing running."""
    with subprocess.Popen(arguments, cwd=ROOT, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, start_new_session=True) as process:
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            return "timeout"
    return "pass" if returncode == 0 else "fail"


def outcome(relative, timeout):
    """What the tests made of the mutant now on disk: killed, survived or not built."""
    built = run(["swift", "build", "--build-tests", "--quiet"], timeout)
    if built != "pass":
        return "killed" if built == "timeout" else "not built"
    feature = next(tests for prefix, tests in FEATURE_TESTS if relative.startswith(prefix))
    if run(["swift", "test", "--skip-build", *feature], timeout) != "pass":
        return "killed"
    return "killed" if run(["swift", "test", "--skip-build"], timeout) != "pass" else "survived"


def sources(paths):
    """Every Swift file under the paths given, or under Sources/, except compiler plugin entries.
    A path outside Sources/ stops the run, so the script never writes anywhere else."""
    allowed = (ROOT / "Sources").resolve()
    roots = [(ROOT / path).resolve() for path in paths] or [allowed]
    for root in roots:
        if root != allowed and allowed not in root.parents:
            sys.exit(f"error: {root} is not under Sources/")
    files = [file for root in roots for file in ([root] if root.is_file() else sorted(root.rglob("*.swift")))]
    resolved = [file.resolve() for file in files]
    for file in resolved:
        if allowed not in file.parents:
            sys.exit(f"error: {file} is not under Sources/")
    return [file for file in resolved if file.name != "Plugin.swift"]


def main():
    parser = argparse.ArgumentParser(description="Mutation testing for Understudy.")
    parser.add_argument("paths", nargs="*", help="files or folders under the package, Sources/ by default")
    parser.add_argument("--list", action="store_true", help="list the mutants without running them")
    parser.add_argument("--timeout", type=int, default=600, help="seconds a build or a test run may take")
    options = parser.parse_args()
    out = ROOT / "mutants.tsv"
    # A file changed before the run would be taken as the original, and an earlier run stopped
    # abruptly may have left a mutant behind: start only from what git has.
    status = ["git", "status", "--porcelain", "--ignored", "--untracked-files=all", "--", "Sources"]
    changed = subprocess.run(status, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    if changed and not options.list:
        sys.exit(f"error: Sources/ has changes git doesn't have; commit or restore them first:\n{changed}")
    # A test that already fails would count every mutant as killed, so the run starts only when the
    # package builds and every test passes as it is.
    build = ["swift", "build", "--build-tests", "--quiet"]
    if not options.list and (run(build, options.timeout) != "pass"
                             or run(["swift", "test", "--skip-build"], options.timeout) != "pass"):
        sys.exit("error: the package doesn't build or a test fails before any change; fix that first")
    # Each result keeps the line it mutated, so a result whose line has changed since is run again.
    rows = [line.split("\t", 4) for line in out.read_text().splitlines()] if out.exists() else []
    done = {(*row[:3], row[4]) for row in rows if len(row) == 5}
    for path in sources(options.paths):
        relative = path.relative_to(ROOT).as_posix()
        original = path.read_text()
        lines = original.split("\n")
        for index, column, change, mutated in mutants(path):
            key = (relative, str(index + 1), f"{column}:{change}")
            if options.list:
                print("\t".join(key))
                continue
            if (*key, lines[index].strip()) in done:
                continue
            try:
                path.write_text("\n".join(lines[:index] + [mutated] + lines[index + 1:]))
                result = outcome(relative, options.timeout)
            finally:
                path.write_text(original)
            with out.open("a") as file:
                file.write("\t".join([*key, result, lines[index].strip()]) + "\n")
            print("\t".join([*key, result]), flush=True)


if __name__ == "__main__":
    sys.exit(main())
