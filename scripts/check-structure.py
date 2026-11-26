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

It reads Swift lexically, so braces and `//` inside strings and comments, block comments included,
count for nothing, and comments of either kind count toward neither a file nor a body. It expects
code that follows CODE_STYLE.md, where every body opens on its declaration's line or on the line
that closes a wrapped signature, and closes on a line of its own. Python 3, nothing else.

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
# A body that opens on its own line: an accessor, or a computed or observed property.
ACCESSOR = re.compile(
    r"^\s*(@\w+(\([^)]*\))?\s+)*((mutating|nonmutating)\s+)?"
    r"(get|set|willSet|didSet|_read|_modify)\b[^{]*\{\s*$"
)
PROPERTY = re.compile(
    r"^\s*(@\w+(\([^)]*\))?\s+)*((public|private|fileprivate|internal|package|open|static|"
    r"class|override|nonisolated|final|lazy|weak|unowned)\s+)*var\s+\w+\s*:[^=]*\{\s*$"
)
# A line no wrapped signature runs on to: the search for a requirement's `{` stops there.
BOUNDARY = re.compile(
    r"^\s*(\}|(@\w+(\([^)]*\))?\s+)*(\w+\s+)*"
    r"(struct|class|enum|protocol|extension|actor|var|let|case|typealias|associatedtype|func|"
    r"init|deinit|subscript)\b)"
)


def swift_files(folder):
    """Every Swift file under `folder`, leaving out build folders."""
    return sorted(path for path in (ROOT / folder).rglob("*.swift") if ".build" not in path.parts)


class Line:
    """One source line as the limits read it: its code with every string's text and every comment
    taken out, and whether it holds a comment and nothing else."""

    def __init__(self, code, comment_only):
        self.code = code
        self.comment_only = comment_only


def read(lines):
    """Reads Swift lexically, carrying block comments (nested ones too) and multiline strings
    across lines, so a brace or `//` inside a string or a comment counts for nothing. A string
    keeps its quotes, so a line of string text still counts as code."""
    result = []
    comment_depth = 0
    multiline = False
    for text in lines:
        code = []
        had_comment = False
        index = 0
        if multiline:
            code.append('"')
        while index < len(text):
            rest = text[index:]
            if comment_depth:
                had_comment = True
                if rest.startswith("/*"):
                    comment_depth, index = comment_depth + 1, index + 2
                elif rest.startswith("*/"):
                    comment_depth, index = comment_depth - 1, index + 2
                else:
                    index += 1
            elif multiline:
                if rest.startswith("\\"):
                    index += 2
                elif rest.startswith('"""'):
                    multiline, index = False, index + 3
                    code.append('"')
                else:
                    index += 1
            elif rest.startswith("//"):
                had_comment = True
                break
            elif rest.startswith("/*"):
                had_comment, comment_depth, index = True, 1, index + 2
            elif rest.startswith('"""'):
                multiline, index = True, index + 3
                code.append('"')
            elif rest.startswith('"'):
                index = string_end(text, index + 1)
                code.append('""')
            else:
                code.append(text[index])
                index += 1
        joined = "".join(code)
        result.append(Line(joined, had_comment and not joined.strip()))
    return result


def string_end(text, index):
    """The index just past the closing quote of the one-line string whose text starts at `index`."""
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == '"':
            return index + 1
        else:
            index += 1
    return index


def code_lines(lines):
    """The number of lines that hold code: not blank, and not only a comment."""
    return sum(1 for line in lines if line.code.strip())


def body_opening(lines, start):
    """The line that opens the body declared at `start`, or None for a requirement with no body.
    The search follows a wrapped signature and stops where no signature can run on."""
    for opening in range(start, len(lines)):
        if opening > start and BOUNDARY.match(lines[opening].code):
            return None
        if lines[opening].code.rstrip().endswith("{"):
            return opening
    return None


def long_bodies(lines):
    """Yields (line number, body length) for each body over the limit."""
    for start, line in enumerate(lines):
        if ACCESSOR.match(line.code) or PROPERTY.match(line.code):
            opening = start
        elif DECLARATION.match(line.code):
            opening = body_opening(lines, start)
            if opening is None:
                continue
        else:
            continue
        depth = 0
        for end in range(opening, len(lines)):
            depth += lines[end].code.count("{") - lines[end].code.count("}")
            if depth <= 0:
                break
        length = end - opening - 1
        if length > BODY_LIMIT:
            yield start + 1, length


def wide_lines(texts, lines):
    """Yields (line number, width, limit) for each line wider than its limit: a line that holds
    only a comment, of either kind, gets the comment limit."""
    for number, (text, line) in enumerate(zip(texts, lines), start=1):
        limit = COMMENT_WIDTH if line.comment_only else CODE_WIDTH
        if len(text) > limit:
            yield number, len(text), limit


def problems():
    """Every problem, as one line each."""
    for folder in ("Sources", "Tests", "Tools"):
        for path in swift_files(folder):
            name = path.relative_to(ROOT)
            texts = path.read_text(encoding="utf-8").splitlines()
            lines = read(texts)
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
            for number, width, limit in wide_lines(texts, lines):
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
