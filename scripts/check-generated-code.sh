#!/usr/bin/env bash
#
#  check-generated-code.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Fails when the amount of code the macros write for the sources under Tests/ differs from the
# budget in Benchmarks/generated-code-budget.txt. The counts come from
# `scripts/compare-expansions.sh --count` and never vary from run to run, so CI enforces them. A pull
# request that changes them, by changing what the macros write or by adding tests that use them,
# updates the budget with --update in the same pull request, so the change shows in its diff and
# the pull request says why.
#
# Usage: scripts/check-generated-code.sh [--update]

set -euo pipefail
cd "$(dirname "$0")/.."

budget=Benchmarks/generated-code-budget.txt
counts=$(scripts/compare-expansions.sh --count)

case "${1:-}" in
    --update)
        printf '%s\n' "$counts" >"$budget"
        echo "Updated $budget:"
        cat "$budget"
        exit 0
        ;;
    "") ;;
    *)
        echo "usage: $0 [--update]" >&2
        exit 2
        ;;
esac

if ! diff -u --label budget "$budget" --label now <(printf '%s\n' "$counts"); then
    echo "error: the code the macros write differs from $budget." >&2
    echo "If the change is intended, run scripts/check-generated-code.sh --update and say why in" >&2
    echo "the pull request." >&2
    exit 1
fi
echo "The code the macros write matches $budget."
