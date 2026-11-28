#!/usr/bin/env bash
#
#  build-docs.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Builds the Understudy library's docs, its DocC catalog with the API docs of its public symbols,
# with warnings as errors, so a broken symbol link, article link or tutorial directive fails here
# instead of on the Swift Package Index. It uses only the Swift toolchain: SwiftPM writes the
# symbol graphs and `docc` builds the catalog, so the package needs no docs plugin. The archive is
# written to .build/docs/Understudy.doccarchive.
#
# Usage: scripts/build-docs.sh

set -euo pipefail
cd "$(dirname "$0")/.."

catalog="Sources/Understudy/Understudy.docc"
output=".build/docs"
graphs="$output/symbol-graphs"

swift package dump-symbol-graph --minimum-access-level public
rm -rf -- "${output:?}"
mkdir -p "$graphs"
# Only the Understudy module's graphs: the others belong to the macros, the samples product and
# swift-syntax, which this catalog doesn't document.
found=0
for graph in .build/*/symbolgraph/Understudy.symbols.json .build/*/symbolgraph/Understudy@*.symbols.json; do
    if [[ -f "$graph" ]]; then
        cp "$graph" "$graphs/"
        found=1
    fi
done
if [[ "$found" -eq 0 ]]; then
    echo "error: swift package dump-symbol-graph wrote no graph for the Understudy module." >&2
    exit 1
fi

docc convert "$catalog" \
    --additional-symbol-graph-dir "$graphs" \
    --fallback-display-name Understudy \
    --fallback-bundle-identifier com.github.joeoct-oss.understudy \
    --output-path "$output/Understudy.doccarchive" \
    --warnings-as-errors
echo "The docs build with no warnings: $output/Understudy.doccarchive"
