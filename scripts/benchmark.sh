#!/usr/bin/env bash
#
#  benchmark.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Measures what Understudy costs a project that uses it, and prints one Markdown table. Each row is
# a median with its range over 10 runs, after warm-up runs. The areas:
# - spies, waiting, clock, traits: the benchmarks in Benchmarks/, a package of its own, run one at
#   a time in debug, as a project builds its tests;
# - macros: how long the macros take to expand every source under Tests/, in process
#   (scripts/compare-expansions.sh --time);
# - code: how much code the macros write for those sources (scripts/compare-expansions.sh --count);
#   it never varies from run to run;
# - build: how long `swift build --build-tests` takes for a generated test target of 100 doubles,
#   each with 10 requirements, and one of 10 protocols, each inheriting the one before: after a
#   change to every double, and after a change to one. Minutes of builds, so it runs only when
#   named, or with --all.
# Timings vary from machine to machine and run to run: compare numbers from the same machine.
#
# Usage: scripts/benchmark.sh [--all] [--only <area>]...

set -euo pipefail
cd "$(dirname "$0")/.."

root="$PWD"
areas=()
all=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) all=true ;;
        --only)
            shift
            areas+=("${1:?--only needs an area}")
            ;;
        *)
            echo "usage: $0 [--all] [--only spies|waiting|clock|traits|macros|code|build]..." >&2
            exit 2
            ;;
    esac
    shift
done
if [[ ${#areas[@]} -eq 0 ]]; then
    areas=(spies waiting clock traits macros code)
    if $all; then
        areas+=(build)
    fi
fi

scratch=$(mktemp -d)
trap 'rm -rf -- "${scratch:?}"' EXIT
table="$scratch/table.md"
touch "$table"

# Runs the Benchmarks/ suite named `$1`, which adds its rows to the table. The package gets the
# root package's pins, so it measures the swift-syntax the package is built and tested with.
run_suite() {
    cp Package.resolved Benchmarks/
    BENCHMARK_TABLE="$table" swift test --package-path Benchmarks --no-parallel --filter "$1" >&2
}

# Adds the macro rows: expansion time, from the tool's median, fastest and slowest lines.
macro_rows() {
    local out
    out=$(scripts/compare-expansions.sh --time)
    local sources median fastest slowest
    sources=$(awk '/^sources/ {print $2}' <<<"$out")
    median=$(awk '/^median/ {print $3}' <<<"$out")
    fastest=$(awk '/^fastest/ {print $3}' <<<"$out")
    slowest=$(awk '/^slowest/ {print $3}' <<<"$out")
    echo "| Macros | Expanding the $sources sources under \`Tests/\` | $median | $fastest–$slowest | ms |" >>"$table"
}

# Adds the generated code rows, which never vary, so they have no range.
code_rows() {
    local out uses lines declarations
    out=$(scripts/compare-expansions.sh --count)
    uses=$(awk '/^macro uses/ {print $3}' <<<"$out")
    lines=$(awk '/^lines written/ {print $3}' <<<"$out")
    declarations=$(awk '/^declarations written/ {print $3}' <<<"$out")
    {
        echo "| Generated code | Lines written for the $uses macro uses under \`Tests/\` | $lines | – | lines |"
        echo "| Generated code | Declarations written for them | $declarations | – | declarations |"
    } >>"$table"
}

# Prints the median, fastest and slowest of the numbers on standard input, as "median|range".
summarize() {
    sort -n | awk '{ v[NR] = $1 } END {
        m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
        printf "%.1f|%.1f–%.1f\n", m, v[1], v[NR]
    }'
}

# The seconds `swift build --build-tests` takes in the package at `$1`; fails when the build does.
build_seconds() {
    local start end
    start=$(date +%s.%N)
    swift build --package-path "$1" --build-tests --quiet >&2 || return 1
    end=$(date +%s.%N)
    awk -v s="$start" -v e="$end" 'BEGIN { printf "%.2f\n", e - s }'
}

# Times 2 warm-up and 10 kept builds of the package at `$1` after touching the files `$3`...,
# and adds the row named `$2`.
build_row() {
    local package="$1" name="$2"
    shift 2
    local times=() run
    for run in $(seq 12); do
        touch "$@"
        local seconds
        seconds=$(build_seconds "$package") || exit 1
        if [[ $run -gt 2 ]]; then
            times+=("$seconds")
        fi
    done
    local summary
    summary=$(printf '%s\n' "${times[@]}" | summarize)
    echo "| Build | $name | ${summary%%|*} | ${summary#*|} | s |" >>"$table"
}

# Adds the build rows, from a package generated in the scratch folder.
build_rows() {
    local package="$scratch/build"
    python3 -I "$root/Benchmarks/generate-build-package.py" "$root" "$package"
    cp Package.resolved "$package/"
    swift build --package-path "$package" --build-tests --quiet >&2
    local doubles=("$package"/Tests/ManyDoubles/*.swift)
    local chain=("$package"/Tests/InheritedProtocols/*.swift)
    build_row "$package" "100 doubles of 10 requirements, every double changed" "${doubles[@]}"
    build_row "$package" "100 doubles of 10 requirements, one double changed" "${doubles[0]}"
    build_row "$package" "10 inherited protocols, every protocol changed" "${chain[@]}"
}

for area in "${areas[@]}"; do
    case "$area" in
        spies) run_suite SpyBenchmarks ;;
        waiting) run_suite WaitingBenchmarks ;;
        clock) run_suite ClockBenchmarks ;;
        traits) run_suite TraitBenchmarks ;;
        macros) macro_rows ;;
        code) code_rows ;;
        build) build_rows ;;
        *)
            echo "error: unknown area '$area'" >&2
            exit 2
            ;;
    esac
done

echo "| Area | Measure | Median | Range | Unit |"
echo "| --- | --- | --- | --- | --- |"
cat "$table"
