#!/usr/bin/env bash
#
#  install-tuist.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Installs the pinned Tuist CLI on a macOS runner and puts it on the job's PATH. The version and
# the SHA-256 of its tuist.zip live here, their one home: the zip is checked before it is opened,
# and a mismatch stops the job. Bump both together, from the release's SHASUMS256.txt.
#
# Usage: scripts/install-tuist.sh

set -euo pipefail

VERSION="4.218.5"
SHA256="5a5431cadf2c276ed559f4cacc38748128307d224d3472bbef04e546c8952d39"

dir="${RUNNER_TEMP:-$(mktemp -d)}/tuist-$VERSION"
zip="$dir.zip"
curl --proto "=https" --tlsv1.2 -fsSL --retry 3 -o "$zip" "https://github.com/tuist/tuist/releases/download/$VERSION/tuist.zip"
if ! echo "$SHA256  $zip" | shasum -a 256 -c --status; then
  echo "::error::tuist.zip $VERSION doesn't match the SHA-256 pinned in scripts/install-tuist.sh."
  exit 1
fi
mkdir -p "$dir"
unzip -q "$zip" -d "$dir"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$dir" >> "$GITHUB_PATH"
fi
"$dir/tuist" version
