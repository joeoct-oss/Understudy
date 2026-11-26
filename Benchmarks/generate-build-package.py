#!/usr/bin/env python3
#
#  generate-build-package.py
#  UnderstudyBenchmarks
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

"""Writes the package that scripts/benchmark.sh builds to time a project's test target build:

- Tests/ManyDoubles: 100 files, each one protocol with 10 requirements of the kinds a test double
  most often has, and `@GenerateSpies` on it;
- Tests/InheritedProtocols: 10 files, each one protocol with 3 requirements that inherits the one
  before it, each with `@GenerateSpies`.

The package depends on Understudy at the path given, so it builds the working tree's macros. It
is written only under the system's temporary folder, so a mistyped path can't overwrite anything
else.

Usage: Benchmarks/generate-build-package.py <Understudy folder> <package folder>
"""

import sys
import tempfile
from pathlib import Path

DOUBLES = 100
CHAIN = 10

PACKAGE = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuildBenchmark",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "Understudy", path: "{root}")],
    targets: [
        .testTarget(name: "ManyDoubles", dependencies: [.product(name: "Understudy", package: "Understudy")]),
        .testTarget(name: "InheritedProtocols", dependencies: [.product(name: "Understudy", package: "Understudy")]),
    ],
    swiftLanguageModes: [.v6]
)
"""

DOUBLE = """import Understudy

@GenerateSpies
protocol Service{n} {{
    func load(id: Int) -> String?
    func save(_ value: String, force: Bool) throws
    func fetch(page: Int) async throws -> [Int]
    func refresh() async
    func count(of name: String) -> Int
    func remove(ids: [Int]) -> Bool
    var name: String {{ get }}
    var isEnabled: Bool {{ get set }}
    subscript(index: Int) -> Double {{ get }}
    static func make() -> Int
}}
"""

LINK = """import Understudy

@GenerateSpies
protocol Link{n}{parent} {{
    func step{n}(_ value: Int) -> Int
    func load{n}() async throws -> String
    var name{n}: String {{ get }}
}}
"""


def write(folder: Path, name: str, text: str) -> None:
    """Writes `text` to `name` in `folder`, making the folder first."""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_text(text)


def main() -> None:
    """Writes the package into the folder given, for the Understudy folder given."""
    root, package = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    if not package.is_relative_to(Path(tempfile.gettempdir()).resolve()):
        sys.exit(f"error: {package} isn't under the temporary folder")
    write(package, "Package.swift", PACKAGE.format(root=root))
    for n in range(DOUBLES):
        write(package / "Tests" / "ManyDoubles", f"Service{n:03}.swift", DOUBLE.format(n=n))
    for n in range(CHAIN):
        parent = f": Link{n - 1}" if n else ""
        write(package / "Tests" / "InheritedProtocols", f"Link{n:02}.swift", LINK.format(n=n, parent=parent))


if __name__ == "__main__":
    main()
