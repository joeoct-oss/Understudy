#!/usr/bin/env python3
#
#  check-structure.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Fails on code that has grown past the package's size limits, so files stay about one thing and
functions stay short (CODE_STYLE.md, "Where code goes"). The limits live here, their one home:

- a file in Sources/ has at most 250 lines of code, and one in Tests/ at most 400; lines of code
  leave out blank lines and comments, so a type with full doc comments isn't split to pass;
- a function, initializer, subscript or accessor body in Sources/ has at most 40 lines;
- every Swift line in Sources/, Tests/ and Tools/ fits in 120 columns, and every comment line in 100.

It reads code that follows CODE_STYLE.md, where every body opens on its declaration's line or on
the line that closes a wrapped signature, and closes on a line of its own. Python 3, nothing else.

Usage: scripts/check-structure.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE_LIMITS = {"Sources": 250, "Tests": 400}
BODY_LIMIT = 40
CODE_WIDTH = 120
COMMENT_WIDTH = 100

DECLARATION = re.compile(
    r"^\s*(@\w+(\([^)]*\))?\s+)*"
    r"((public|private|fileprivate|internal|package|open|static|class|override|mutating|"
    r"nonisolated|final|convenience|required|isolated)\s+)*"
    r"(func|init|deinit|subscript)\b"
)


def swift_files(folder):
    """Every Swift file under `folder`, leaving out build folders."""
    return sorted(path for path in (ROOT / folder).rglob("*.swift") if ".build" not in path.parts)


def code_lines(lines):
    """The number of lines that are neither blank nor comments."""
    return sum(1 for line in lines if line.strip() and not line.strip().startswith("//"))


def long_bodies(lines):
    """Yields (line number, body length) for each body over the limit."""
    for start, line in enumerate(lines):
        if not DECLARATION.match(line):
            continue
        opening = start
        while opening < len(lines) and not lines[opening].rstrip().endswith("{"):
            opening += 1
            if opening < len(lines) and DECLARATION.match(lines[opening]):
                break
        # A requirement with no body, such as one in a protocol, reaches the next declaration first.
        if opening >= len(lines) or not lines[opening].rstrip().endswith("{"):
            continue
        depth = 0
        for end in range(opening, len(lines)):
            depth += lines[end].count("{") - lines[end].count("}")
            if depth <= 0:
                break
        length = end - opening - 1
        if length > BODY_LIMIT:
            yield start + 1, length


def wide_lines(lines):
    """Yields (line number, width, limit) for each line wider than its limit."""
    for number, line in enumerate(lines, start=1):
        limit = COMMENT_WIDTH if line.strip().startswith("//") else CODE_WIDTH
        if len(line) > limit:
            yield number, len(line), limit


def problems():
    """Every problem, as one line each."""
    for folder in ("Sources", "Tests", "Tools"):
        for path in swift_files(folder):
            name = path.relative_to(ROOT)
            lines = path.read_text(encoding="utf-8").splitlines()
            limit = FILE_LIMITS.get(folder)
            count = code_lines(lines)
            if limit is not None and count > limit:
                yield f"{name}: {count} lines of code, more than {limit}; split it by job"
            if folder == "Sources":
                for number, length in long_bodies(lines):
                    yield (
                        f"{name}:{number}: a body of {length} lines, more than {BODY_LIMIT}; "
                        "split it into named steps"
                    )
            for number, width, limit in wide_lines(lines):
                yield f"{name}:{number}: {width} columns, more than {limit}"


def main():
    found = list(problems())
    for problem in found:
        print(f"error: {problem}", file=sys.stderr)
    if found:
        return 1
    print("Every file and body is within the package's size limits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
