#!/usr/bin/env bash
#
#  compare-expansions.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Shows how the code the macros write changed between a commit and the working tree: prints the
# difference between the two records, and nothing when the macros write the same code and give the
# same messages. Each record runs the macros of its own commit over the same files: every Swift file
# under Tests/ in the working tree, so it covers every double the tests build and every source the
# macro tests expand from a plain string literal. A source the macro tests build with interpolation,
# such as most refusals, isn't in it; their tests check those messages. With `--record`, prints the
# working tree's record instead of a difference. The tool is Tools/ExpansionRecord.
#
# Usage: scripts/compare-expansions.sh <git ref>
#        scripts/compare-expansions.sh --record

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <git ref> | --record" >&2
    exit 2
fi

root="$PWD"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mapfile -t inputs < <(find "$root/Tests" -name '*.swift' | LC_ALL=C sort)

# The tool is built in .build, which git ignores, so swift-syntax is built once and reused.
tool="$root/.build/expansion-record"

# Prints the record of the macro sources in `$1`, a folder that holds Sources/ of some commit.
record() {
    local sources="$1"
    mkdir -p "$tool"
    rm -rf "$tool/Sources"
    cp -R "$root/Tools/ExpansionRecord/." "$tool/"
    cp -R "$sources/Sources/UnderstudyMacros" "$sources/Sources/UnderstudySamplesMacros" "$tool/Sources/"
    cp "$root/Package.resolved" "$tool/"
    swift build --package-path "$tool" --product ExpansionRecord --quiet >&2
    "$(swift build --package-path "$tool" --show-bin-path)/ExpansionRecord" "${inputs[@]}" |
        sed "s|$root/||"
}

if [[ "$1" == "--record" ]]; then
    record "$root"
    exit 0
fi

base="$scratch/base"
mkdir -p "$base"
git archive "$1" Sources | tar -x -C "$base"
record "$base" >"$scratch/base.txt"
record "$root" >"$scratch/head.txt"
diff -u --label "$1" --label "working tree" "$scratch/base.txt" "$scratch/head.txt" || true
