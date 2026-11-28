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
  out on both sides, since a test file adds one to keep its types to itself;
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

BLOCK = re.compile(r"^```swift\s*$")
FENCE = re.compile(r"^```\s*$")
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
        if line:
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


def article_blocks(name, text):
    """Each swift block of an article: (where, code, reason it isn't compiled or None)."""
    blocks = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        if not BLOCK.match(lines[index]):
            index += 1
            continue
        before = next((line for line in reversed(lines[:index]) if line.strip()), "")
        marked = NOT_COMPILED.match(before.strip())
        start = index + 1
        index = start
        while index < len(lines) and not FENCE.match(lines[index]):
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
    articles = {str(path.relative_to(ROOT)): path.read_text() for path in sorted(CATALOG.rglob("*.md"))}
    tutorials = {str(path.relative_to(ROOT)): path.read_text() for path in sorted(CATALOG.rglob("*.tutorial"))}
    resources = {path.name: path.read_text() for path in sorted(CATALOG.rglob("*.swift"))}
    guides = {str(path.relative_to(ROOT)): path.read_text() for path in sorted(GUIDES.rglob("*.swift"))}
    return articles, tutorials, resources, guides


def self_check():
    """Runs the script's own cases: what passes, and each kind of drift it must catch."""
    test = {"Guides/A.swift": "// header\n\nprivate final class Spy {\n    func call() {\n        run()\n    }\n}\n"}
    article = "# A\n\n```swift\nfinal class Spy {\n  func call() {\n      run()\n\n  }\n```\n"
    drifted = "# A\n\n```swift\nfinal class Spy {\n    func call() {\n        walk()\n```\n"
    manifest = "# A\n\n<!-- not compiled: a package manifest -->\n```swift\nlet package = Package()\n```\n"
    tutorial = '@Section(title: "A") {\n@Code(name: "S.swift", file: "s1.swift")\n@Code(name: "S.swift", file: "s2.swift")\n}'
    steps = {"s1.swift": "// header\nfinal class Spy {\n}\n", "s2.swift": "final class Spy {\nfunc call() {\nrun()\n}\n}"}
    bad_steps = {"s1.swift": "final class Other {\n}\n", "s2.swift": steps["s2.swift"]}
    cases = [
        ("an example in a guide test passes", problems({"a.md": article}, {}, {}, test)[0], []),
        ("a drifted example fails", len(problems({"a.md": drifted}, {}, {}, test)[0]), 1),
        ("a marked manifest is listed, not checked", problems({"a.md": manifest}, {}, {}, test), ([], ["a.md:5: a package manifest"])),
        ("an unmarked manifest fails", len(problems({"a.md": manifest.replace("<!-- not compiled: a package manifest -->\n", "")}, {}, {}, test)[0]), 1),
        ("a tutorial's steps that build to its last file pass", problems({}, {"t": tutorial}, steps, {"G.swift": steps["s2.swift"]})[0], []),
        ("a step that isn't part of the last file fails", len(problems({}, {"t": tutorial}, bad_steps, {"G.swift": steps["s2.swift"]})[0]), 1),
        ("a last file no test holds fails", len(problems({}, {"t": tutorial}, steps, {"G.swift": "final class Spy {}"})[0]), 1),
        ("a missing code file fails", len(problems({}, {"t": tutorial}, {}, {})[0]), 2),
        ("a tutorial manifest is listed", problems({}, {"t": '@Code(name: "P", file: "p.swift")'}, {"p.swift": "// swift-tools-version: 6.0\nlet p = 1"}, {})[1], ["p.swift: a package manifest"]),
    ]
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
        print("Write each example in a test under Tests/UnderstudyTests/Guides/ exactly as the docs show it.", file=sys.stderr)
        return 1
    print("Every example in the docs is in a guide test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
