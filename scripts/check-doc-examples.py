#!/usr/bin/env python3
#
#  check-doc-examples.py
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Fails when an example in the DocC catalog isn't one the tests compile, so the guides can't
drift from the API. The rules live here, their one home:

- every ```swift block in an article (Sources/Understudy/Understudy.docc/**/*.md) must appear,
  line by line and in order with nothing between its lines, in a file under
  Tests/UnderstudyTests/Guides/, which builds and runs with the other tests;
- in a tutorial (*.tutorial), the last code file of each name in a section (the step a reader
  ends on) must appear the same way, and each earlier file of that name in the section must be
  part of it: its lines, in order, all in the last one;
- lines are compared with their indentation and runs of spaces collapsed, blank lines skipped, a
  code file's opening header comment left out, and a leading `private ` or `fileprivate ` left
  out on both sides, since a test file adds one to keep its types to itself; `import` lines
  are left out too, since a tutorial's tests import the reader's app and the guide tests have
  its code in their own target;
- a block ends at a fence of three or more backticks, after at most three spaces, with nothing
  after it but spaces, at least as long as the one that opened it, as Markdown reads it;
- a block that can't be a test, such as a package manifest, is marked on the line before it with
  `<!-- not compiled: <why> -->`, and a tutorial file that opens with `// swift-tools-version` is
  a manifest. Each one is listed in the output with its reason.

Python 3, nothing else.

Usage: scripts/check-doc-examples.py              checks the catalog against the tests
       scripts/check-doc-examples.py --self-check runs its own cases and exits
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Sources/Understudy/Understudy.docc"
GUIDES = ROOT / "Tests/UnderstudyTests/Guides"

BLOCK = re.compile(r"^ {0,3}(`{3,})swift\s*$")
FENCE = re.compile(r"^ {0,3}(`{3,})\s*$")
IMPORT = re.compile(r"^import ")
NOT_COMPILED = re.compile(r"^<!--\s*not compiled:\s*(.+?)\s*-->\s*$")
SECTION = re.compile(r"@Section\s*\(")
CODE = re.compile(r'@Code\s*\(\s*name:\s*"([^"]+)"\s*,\s*file:\s*"([^"]+)"\s*\)')
ACCESS = re.compile(r"^(private|fileprivate) ")


def normalized(text):
    """The lines of `text` as they are compared: the opening header comment left out, each line
    stripped with runs of spaces collapsed, blank lines skipped, and a leading `private ` or
    `fileprivate ` taken off."""
    lines = text.splitlines()
    while lines and (lines[0].strip().startswith("//") or not lines[0].strip()):
        if lines[0].strip().startswith("// swift-tools-version"):
            break
        lines.pop(0)
    result = []
    for line in lines:
        line = " ".join(line.split())
        if line and not IMPORT.match(line):
            result.append(ACCESS.sub("", line))
    return result


def contains_run(haystack, needle):
    """Whether `needle` appears in `haystack` as one unbroken run."""
    if not needle:
        return True
    width = len(needle)
    return any(haystack[start:start + width] == needle for start in range(len(haystack) - width + 1))


def is_part_of(earlier, last):
    """Whether every line of `earlier` is in `last`, in the same order."""
    position = 0
    for line in earlier:
        while position < len(last) and last[position] != line:
            position += 1
        if position == len(last):
            return False
        position += 1
    return True


def closes(line, width):
    """Whether `line` is a fence that closes a block opened with `width` backticks."""
    fence = FENCE.match(line)
    return fence is not None and len(fence.group(1)) >= width


def article_blocks(name, text):
    """Each swift block of an article: (where, code, reason it isn't compiled or None)."""
    blocks = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        opening = BLOCK.match(lines[index])
        if not opening:
            index += 1
            continue
        before = next((line for line in reversed(lines[:index]) if line.strip()), "")
        marked = NOT_COMPILED.match(before.strip())
        start = index + 1
        index = start
        while index < len(lines) and not closes(lines[index], len(opening.group(1))):
            index += 1
        code = "\n".join(lines[start:index])
        blocks.append((f"{name}:{start + 1}", code, marked.group(1) if marked else None))
        index += 1
    return blocks


def tutorial_files(text):
    """The code files of a tutorial, grouped by section and name, in step order."""
    groups = {}
    for number, section in enumerate(SECTION.split(text)):
        for name, file in CODE.findall(section):
            groups.setdefault((number, name), []).append(file)
    return list(groups.values())


def problems(articles, tutorials, resources, guides):
    """What is wrong, and what was left out on purpose. `articles` and `tutorials` map a name to
    its text, `resources` a code file's name to its text, and `guides` a test file's name to its
    text."""
    errors = []
    skipped = []
    tests = {name: normalized(text) for name, text in guides.items()}

    def found(code):
        wanted = normalized(code)
        return any(contains_run(lines, wanted) for lines in tests.values())

    for name, text in sorted(articles.items()):
        for where, code, reason in article_blocks(name, text):
            if reason:
                skipped.append(f"{where}: {reason}")
            elif not found(code):
                errors.append(f"{where}: this example isn't in any file under Tests/UnderstudyTests/Guides/")
    for name, text in sorted(tutorials.items()):
        for files in tutorial_files(text):
            missing = [file for file in files if file not in resources]
            if missing:
                errors.extend(f"{name}: no code file named {file}" for file in missing)
                continue
            last = files[-1]
            if normalized(resources[last])[:1] and normalized(resources[last])[0].startswith(
                "// swift-tools-version"
            ):
                skipped.append(f"{last}: a package manifest")
                continue
            if not found(resources[last]):
                errors.append(f"{last}: this file isn't in any file under Tests/UnderstudyTests/Guides/")
            for earlier in files[:-1]:
                if not is_part_of(normalized(resources[earlier]), normalized(resources[last])):
                    errors.append(f"{earlier}: this step isn't part of {last}, the section's last step")
    return errors, skipped


def read_tree():
    """The catalog's articles, tutorials and code files, and the guide tests, from the repo."""

    def texts(folder, pattern, key):
        return {key(path): path.read_text(encoding="utf-8") for path in sorted(folder.rglob(pattern))}

    def relative(path):
        return str(path.relative_to(ROOT))

    articles = texts(CATALOG, "*.md", relative)
    tutorials = texts(CATALOG, "*.tutorial", relative)
    resources = texts(CATALOG, "*.swift", lambda path: path.name)
    guides = texts(GUIDES, "*.swift", relative)
    return articles, tutorials, resources, guides


def self_check_fixtures():
    """The texts the self-check cases run `problems` on, by name."""
    marker = "<!-- not compiled: a package manifest -->\n"
    manifest = "# A\n\n" + marker + "```swift\nlet package = Package()\n```\n"
    last_step = "final class Spy {\nfunc call() {\nrun()\n}\n}"
    return {
        "test": {
            "Guides/A.swift": "// header\n\nprivate final class Spy {\n    func call() {\n        run()\n    }\n}\n"
        },
        "article": "# A\n\n```swift\nfinal class Spy {\n  func call() {\n      run()\n\n  }\n```\n",
        "drifted": "# A\n\n```swift\nfinal class Spy {\n    func call() {\n        walk()\n```\n",
        "manifest": manifest,
        "unmarked": manifest.replace(marker, ""),
        "tutorial": (
            '@Section(title: "A") {\n'
            '@Code(name: "S.swift", file: "s1.swift")\n'
            '@Code(name: "S.swift", file: "s2.swift")\n'
            "}"
        ),
        "steps": {"s1.swift": "// header\nfinal class Spy {\n}\n", "s2.swift": last_step},
        "bad_steps": {"s1.swift": "final class Other {\n}\n", "s2.swift": last_step},
        "holding_test": {"G.swift": last_step},
        "other_test": {"G.swift": "final class Spy {}"},
        "long_fence": "# A\n\n```swift\nfinal class Spy {\n    func call() {\n        run()\n````\n\nProse after it.\n",
        "indented_fence": "# A\n\n```swift\nfinal class Spy {\n    func call() {\n        run()\n   ```\n\nProse.\n",
        "importing_test": {"Guides/A.swift": "import Understudy\nfinal class Spy {\n}\n"},
        "importing": "# A\n\n```swift\nimport Restaurant\nimport Understudy\nfinal class Spy {\n}\n```\n",
        "manifest_tutorial": {"t": '@Code(name: "Package", file: "package.swift")'},
        "manifest_file": {"package.swift": "// swift-tools-version: 6.0\nlet package = Package()"},
    }


def self_check_cases():
    """The script's own cases, as (name, what `problems` gave, what it should give): what passes,
    and each kind of drift it must catch."""
    fixture = self_check_fixtures()

    def article_problems(article, guides=None):
        return problems({"a.md": article}, {}, {}, fixture["test"] if guides is None else guides)

    def tutorial_problems(steps, guides):
        return problems({}, {"t": fixture["tutorial"]}, steps, guides)[0]

    return [
        ("an example in a guide test passes", article_problems(fixture["article"])[0], []),
        ("a drifted example fails", len(article_problems(fixture["drifted"])[0]), 1),
        (
            "a marked manifest is listed, not checked",
            article_problems(fixture["manifest"]),
            ([], ["a.md:5: a package manifest"]),
        ),
        ("an unmarked manifest fails", len(article_problems(fixture["unmarked"])[0]), 1),
        (
            "a tutorial's steps that build to its last file pass",
            tutorial_problems(fixture["steps"], fixture["holding_test"]),
            [],
        ),
        (
            "a step that isn't part of the last file fails",
            len(tutorial_problems(fixture["bad_steps"], fixture["holding_test"])),
            1,
        ),
        ("a last file no test holds fails", len(tutorial_problems(fixture["steps"], fixture["other_test"])), 1),
        ("a longer closing fence ends the block", article_problems(fixture["long_fence"])[0], []),
        ("a closing fence after three spaces ends the block", article_problems(fixture["indented_fence"])[0], []),
        (
            "import lines are left out",
            article_problems(fixture["importing"], fixture["importing_test"])[0],
            [],
        ),
        ("a missing code file fails", len(tutorial_problems({}, {})), 2),
        (
            "a tutorial manifest is listed",
            problems({}, fixture["manifest_tutorial"], fixture["manifest_file"], {})[1],
            ["package.swift: a package manifest"],
        ),
    ]


def self_check():
    """Runs the script's own cases and says which failed."""
    cases = self_check_cases()
    failed = [name for name, actual, expected in cases if actual != expected]
    for name in failed:
        print(f"self-check failed: {name}", file=sys.stderr)
    if failed:
        return 1
    print(f"All {len(cases)} self-check cases pass.")
    return 0


def main():
    if sys.argv[1:] == ["--self-check"]:
        return self_check()
    if sys.argv[1:]:
        print(__doc__.split("Usage:")[1].strip(), file=sys.stderr)
        return 2
    errors, skipped = problems(*read_tree())
    for line in skipped:
        print(f"not compiled, on purpose: {line}")
    for line in errors:
        print(f"error: {line}", file=sys.stderr)
    if errors:
        print(
            "Write each example in a test under Tests/UnderstudyTests/Guides/ exactly as the docs show it.",
            file=sys.stderr,
        )
        return 1
    print("Every example in the docs is in a guide test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
