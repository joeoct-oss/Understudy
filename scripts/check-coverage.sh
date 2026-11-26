#!/usr/bin/env bash
#
#  check-coverage.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Runs the tests with code coverage and fails on any line of the package's sources that no test ran.
# The spies are measured in the runtime's tests, and each set of macros in its own macro tests,
# which run them in process. `UnderstudySamples` holds only macro declarations, so it has no lines
# to measure. `Plugin.swift` is left out: it is the compiler plugin's entry point, which only the
# compiler starts. Extra arguments go to `swift test`. With COVERAGE_LCOV set to a path, it also
# writes the measured lines there as one LCOV file, each set of sources from its own tests, for a
# coverage report such as Codecov's.
#
# Usage: [COVERAGE_LCOV=path] scripts/check-coverage.sh [swift test arguments]

set -euo pipefail
cd "$(dirname "$0")/.."

# A restored build cache can hold coverage profiles from an earlier run, which would count lines
# that this run's tests never reach, so they are removed first.
codecov=$(swift test --show-codecov-path)
codecov=$(dirname "$codecov")
if [[ "$codecov" != */codecov ]]; then
    echo "error: unexpected coverage folder '$codecov'" >&2
    exit 1
fi
rm -rf "$codecov"
# Swift Testing runs tests in parallel, and the coverage counters aren't atomic by default, so two
# threads that run the same code at once can lose a count. A line's count can be worked out as one
# counter minus another, so a lost count can show a line that ran as never run. Atomic counters
# keep every count.
swift test --enable-code-coverage -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all "$@"

build=$(swift build --show-bin-path)
profile="$(dirname "$(swift test --show-codecov-path)")/default.profdata"
status=0
if [[ -n "${COVERAGE_LCOV:-}" ]]; then
    : >"$COVERAGE_LCOV"
fi

# Prints the LCOV records of the files under `$2`, as measured by the test bundle `$1`.
lcov_for() {
    local bundle="$1" sources="$2"
    llvm-cov export "$bundle" -instr-profile="$profile" -format=lcov \
        -ignore-filename-regex='(\.build|Tests|Plugin\.swift)' |
        awk -v sources="$sources" '
            /^SF:/ { keep = index(substr($0, 4), sources) > 0 }
            keep { print }
        '
}

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

# The test binary that holds the target `$1`. Newer toolchains build one per test target, a shared
# library on Linux or a .xctest bundle on Apple platforms; Swift 6.2 builds one for the whole
# package, `UnderstudyPackageTests.xctest`, a plain file on Linux.
bundle_for() {
    local name="$1" candidate
    for candidate in "$build/$name.so" "$build/$name.xctest/Contents/MacOS/$name" \
        "$build/UnderstudyPackageTests.xctest/Contents/MacOS/UnderstudyPackageTests" \
        "$build/UnderstudyPackageTests.xctest"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done
    echo "error: no test binary for $name in $build" >&2
    return 1
}

for pair in "UnderstudyTests Sources/Understudy/" "UnderstudyMacrosTests Sources/UnderstudyMacros/" \
    "UnderstudySamplesMacrosTests Sources/UnderstudySamplesMacros/"; do
    read -r name sources <<<"$pair"
    bundle=$(bundle_for "$name")
    missed=$(uncovered "$bundle" "$PWD/$sources")
    if [[ -n "${COVERAGE_LCOV:-}" ]]; then
        lcov_for "$bundle" "$PWD/$sources" >>"$COVERAGE_LCOV"
    fi
    if [[ -n "$missed" ]]; then
        echo "error: lines in $sources that no test runs:" >&2
        echo "$missed" >&2
        status=1
    else
        echo "Every line of $sources runs in $name."
    fi
done
exit "$status"
