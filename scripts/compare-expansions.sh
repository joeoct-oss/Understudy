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
# working tree's record instead of a difference; with `--count`, how much code the working tree's
# macros write for those files; with `--time`, how long they take to expand them. The tool is
# Tools/ExpansionRecord.
#
# Usage: scripts/compare-expansions.sh <git ref>
#        scripts/compare-expansions.sh --record | --count | --time

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <git ref> | --record | --count | --time" >&2
    exit 2
fi

root="$PWD"
scratch=$(mktemp -d)
trap 'rm -rf -- "${scratch:?}"' EXIT
# A read loop, not mapfile, which the Bash 3.2 that macOS ships doesn't have.
inputs=()
while IFS= read -r file; do
    inputs+=("$file")
done < <(find "$root/Tests" -name '*.swift' | LC_ALL=C sort)

# The tool is built in .build, which git ignores, so swift-syntax is built once and reused.
tool="$root/.build/expansion-record"

# Prints the record of the macro sources in `$1`, a folder that holds Sources/ of some commit, or
# with a second argument, `--count` or `--time`, what that mode of the tool prints.
record() {
    local sources="$1"
    local mode=("${@:2}")
    mkdir -p "$tool"
    rm -rf -- "${tool:?}/Sources"
    cp -R "$root/Tools/ExpansionRecord/." "$tool/"
    cp -R "$sources/Sources/UnderstudyMacros" "$sources/Sources/UnderstudySamplesMacros" "$tool/Sources/"
    # The plugins' entry points start a compiler plugin, which a tool can't link.
    find "$tool/Sources" -name Plugin.swift -delete
    # The tool pins swift-syntax in its own Package.resolved; the package's pin replaces it here,
    # so the record always uses the swift-syntax the package is built with.
    cp "$root/Package.resolved" "$tool/"
    swift build --package-path "$tool" --product ExpansionRecord --quiet >&2
    "$(swift build --package-path "$tool" --show-bin-path)/ExpansionRecord" ${mode[@]+"${mode[@]}"} -- "${inputs[@]}" |
        sed "s|$root/||"
}

case "$1" in
    --record)
        record "$root"
        exit 0
        ;;
    --count | --time)
        record "$root" "$1"
        exit 0
        ;;
    *)
        # Anything else is the comparison below.
        ;;
esac

# The ref is resolved to a commit first, so it can never be read as an option.
if ! commit=$(git rev-parse --verify --quiet --end-of-options "$1^{commit}"); then
    echo "error: '$1' is not a commit" >&2
    exit 2
fi
base="$scratch/base"
mkdir -p "$base"
git archive "$commit" -- Sources | tar -x -C "$base"
record "$base" >"$scratch/base.txt"
record "$root" >"$scratch/head.txt"
diff -u --label "$1" --label "working tree" "$scratch/base.txt" "$scratch/head.txt" || true
