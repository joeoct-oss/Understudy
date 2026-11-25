#!/usr/bin/env bash
#
#  check-coverage.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Runs the tests with code coverage and fails on any line of the package's sources that no test ran.
# The spies are measured in the runtime's tests, and the macros in the macro tests, which run them
# in process. `Plugin.swift` is left out: it is the compiler plugin's entry point, which only the
# compiler starts. Extra arguments go to `swift test`.
#
# Usage: scripts/check-coverage.sh [swift test arguments]

set -euo pipefail
cd "$(dirname "$0")/.."

swift test --enable-code-coverage "$@"

build=$(swift build --show-bin-path)
profile="$(dirname "$(swift test --show-codecov-path)")/default.profdata"
status=0

# Prints "file:line" for each line of `$2` that the test bundle `$1` never ran.
uncovered() {
    local bundle="$1" sources="$2"
    llvm-cov export "$bundle" -instr-profile="$profile" -format=lcov \
        -ignore-filename-regex='(\.build|Tests|Plugin\.swift)' |
        awk -F'[:,]' -v sources="$sources" '
            /^SF:/ { file = substr($0, 4) }
            /^DA:/ && $3 == 0 && index(file, sources) { print file ":" $2 }
        '
}

# A test bundle is a .xctest bundle on Apple platforms and a shared library on Linux.
bundle_for() {
    local name="$1"
    if [[ -d "$build/$name.xctest" ]]; then
        echo "$build/$name.xctest/Contents/MacOS/$name"
    else
        echo "$build/$name.so"
    fi
}

for pair in "UnderstudyTests Sources/Understudy/" "UnderstudyMacrosTests Sources/UnderstudyMacros/"; do
    read -r name sources <<<"$pair"
    missed=$(uncovered "$(bundle_for "$name")" "$PWD/$sources")
    if [[ -n "$missed" ]]; then
        echo "error: lines in $sources that no test runs:" >&2
        echo "$missed" >&2
        status=1
    else
        echo "Every line of $sources runs in $name."
    fi
done
exit "$status"
