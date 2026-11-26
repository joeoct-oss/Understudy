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

- a file in Sources/ has at most 250 lines of code, and one in Tests/ or Benchmarks/ at most 400;
  lines of code leave out blank lines and comments, so a type with full doc comments isn't split
  to pass;
- a function, initializer, subscript or accessor body in Sources/ has at most 40 lines;
- every Swift line in Sources/, Tests/, Tools/ and Benchmarks/ fits in 120 columns, and every
  comment line in 100.

It reads Swift lexically, so braces and `//` inside strings, regex literals and comments, block
comments included, count for nothing. Comments of either kind don't count toward a file, but a
body's length counts every line between its braces. It expects code that follows CODE_STYLE.md,
where every body opens on its declaration's line or on the line that closes a wrapped signature,
and closes on a line of its own. Python 3, nothing else.

Usage: scripts/check-structure.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE_LIMITS = {"Sources": 250, "Tests": 400, "Benchmarks": 400}
BODY_LIMIT = 40
CODE_WIDTH = 120
COMMENT_WIDTH = 100

DECLARATION = re.compile(
    r"^\s*(@\w+(\([^)]*\))?\s+)*"
    r"((public|private|fileprivate|internal|package|open|static|class|override|mutating|"
    r"nonmutating|nonisolated|final|convenience|required|isolated|prefix|postfix|infix|"
    r"dynamic|optional|distributed)\s+)*"
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
    reader = Reader()
    return [reader.line(text) for text in lines]


class Reader:
    """Reads one line at a time, remembering the block comment or multiline string a line ends
    inside, for the next one."""

    def __init__(self):
        self.comment_depth = 0
        self.multiline = False

    def line(self, text):
        """The line's code, with comments taken out and strings emptied."""
        code = ['"'] if self.multiline else []
        had_comment = False
        index = 0
        while index < len(text):
            if self.comment_depth:
                had_comment = True
                index = self.in_comment(text, index)
            elif self.multiline:
                index = self.in_multiline(text, index, code)
            elif text.startswith("//", index):
                had_comment = True
                break
            else:
                had_comment = had_comment or text.startswith("/*", index)
                index = self.in_code(text, index, code)
        joined = "".join(code)
        return Line(joined, had_comment and not joined.strip())

    def in_comment(self, text, index):
        """Steps through a block comment, counting nested ones; the index after the step."""
        if text.startswith("/*", index):
            self.comment_depth += 1
            return index + 2
        if text.startswith("*/", index):
            self.comment_depth -= 1
            return index + 2
        return index + 1

    def in_multiline(self, text, index, code):
        """Steps through a multiline string, skipping escapes; the index after the step."""
        if text.startswith("\\", index):
            return index + 2
        if text.startswith('"""', index):
            self.multiline = False
            code.append('"')
            return index + 3
        return index + 1

    def in_code(self, text, index, code):
        """Steps through code, opening a comment, a string or a regex literal; the index after
        the step."""
        if text.startswith("/*", index):
            self.comment_depth = 1
            return index + 2
        if text.startswith('"""', index):
            self.multiline = True
            code.append('"')
            return index + 3
        if text.startswith('"', index):
            code.append('""')
            return string_end(text, index + 1)
        if regex_opens(text, index):
            code.append("#//#")
            return regex_end(text, index)
        code.append(text[index])
        return index + 1


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


def regex_opens(text, index):
    """Whether a regex literal starts at `index`: an extended one, `#/.../#`, anywhere, or a bare
    `/.../` where a value starts, after `=`, `(`, `,`, `:`, `[`, `return` or at the line's start,
    so a division is never taken for one."""
    rest = text[index:]
    if re.match(r"#+/", rest):
        return True
    if not rest.startswith("/") or rest.startswith("//") or rest.startswith("/*"):
        return False
    before = text[:index].rstrip()
    return before == "" or before.endswith(("=", "(", ",", ":", "[", "return"))


def regex_end(text, index):
    """The index just past the regex literal that starts at `index`, or the line's end."""
    hashes = len(text[index:]) - len(text[index:].lstrip("#"))
    closing = "/" + "#" * hashes
    index += hashes + 1
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text.startswith(closing, index):
            return index + len(closing)
        else:
            index += 1
    return index


def code_lines(lines):
    """The number of lines that hold code: not blank, and not only a comment."""
    return sum(1 for line in lines if line.code.strip())


def body_opening(lines, start):
    """The line that opens the body declared at `start`, or None for a requirement with no body.
    The search follows a wrapped signature, skips the closures of its default arguments, and stops
    where no signature can run on."""
    depth = 0
    for opening in range(start, len(lines)):
        code = lines[opening].code
        if opening > start and depth == 0 and BOUNDARY.match(code):
            return None
        depth += sum(code.count(mark) for mark in "([") - sum(code.count(mark) for mark in ")]")
        # Inside the parameter list, a `{` opens a default argument's closure, not the body.
        if depth <= 0 and code.rstrip().endswith("{"):
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
        # Count from the body's `{`, so a default closure's `}` earlier on the line can't cancel it.
        rest = lines[opening].code.rstrip()
        rest = rest[rest.rfind("{") + 1:]
        depth = 1 + rest.count("{") - rest.count("}")
        end = opening
        while depth > 0 and end + 1 < len(lines):
            end += 1
            depth += lines[end].code.count("{") - lines[end].code.count("}")
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
    for folder in ("Sources", "Tests", "Tools", "Benchmarks"):
        for path in swift_files(folder):
            yield from file_problems(path, folder)


def file_problems(path, folder):
    """The problems of one file in `folder`, as one line each."""
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
