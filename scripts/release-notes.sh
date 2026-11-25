#!/usr/bin/env bash
#
#  release-notes.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Finds the newest version in CHANGELOG.md: the first heading after `## Unreleased`, which must
# read `## X.Y.Z - YYYY-MM-DD`. Prints the version and writes that version's notes, up to the next
# `## ` heading with blank lines trimmed at both ends, to the notes file. Fails when there's no
# version heading, the heading has another form, or the notes are empty. The Release workflow uses
# it; run it locally to see what a merge would publish.
#
# Usage: scripts/release-notes.sh <notes file> [changelog, default CHANGELOG.md]

set -euo pipefail

notes="${1:?Usage: scripts/release-notes.sh <notes file> [changelog]}"
changelog="${2:-CHANGELOG.md}"

heading=$(grep -m 1 -E '^## ' <(grep -v -E '^## Unreleased[[:space:]]*$' "$changelog") || true)
if [[ -z "$heading" ]]; then
    echo "error: $changelog has no version heading below ## Unreleased." >&2
    exit 1
fi

pattern='^## ([0-9]+\.[0-9]+\.[0-9]+) - [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$'
if [[ ! "$heading" =~ $pattern ]]; then
    echo "error: '$heading' should read '## X.Y.Z - YYYY-MM-DD'." >&2
    exit 1
fi
version="${BASH_REMATCH[1]}"

# The section's lines, from after its heading up to the next `## ` heading, with blank lines
# trimmed at both ends.
awk -v heading="$heading" '
    $0 == heading { inside = 1; next }
    inside && /^## / { exit }
    inside { lines[++count] = $0 }
    END {
        first = 1; while (first <= count && lines[first] ~ /^[[:space:]]*$/) first++
        last = count; while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = first; i <= last; i++) print lines[i]
    }
' "$changelog" > "$notes"

if [[ ! -s "$notes" ]]; then
    echo "error: the $version section of $changelog has no notes." >&2
    exit 1
fi

echo "$version"
