#!/usr/bin/env bash
#
#  sonar-scan.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Runs SonarQube Cloud's analysis and waits for its quality gate: exits non-zero when the gate
# fails, so the checks workflow runs nothing else. Settings are in sonar-project.properties.
# - The scanner comes from Maven Central at a pinned version and is checked against its SHA-256.
# - The version Sonar records is the newest version in CHANGELOG.md (scripts/release-notes.sh), so
#   the release commit itself starts a new version and new code on main is everything after it. A
#   pull request is always compared with main.
# - Needs SONAR_TOKEN. Pull requests from forks get no secrets, so they stop here.
set -euo pipefail

scanner_version="8.5.0.16571"
scanner_sha256="900b76db8a0efb845ed45d7a44b522bda05c8059bcaa6864c9e969de3a8c05f9"
maven="https://repo1.maven.org/maven2/org/sonarsource/scanner/cli/sonar-scanner-cli"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "::error::SONAR_TOKEN is not set. A pull request from a fork gets no secrets, so a maintainer pushes its branch to this repository to run the checks."
  exit 1
fi

work_dir="${RUNNER_TEMP:-$(mktemp -d)}"
jar="$work_dir/sonar-scanner-cli-$scanner_version.jar"
curl --fail --silent --show-error --location --proto '=https' \
  "$maven/$scanner_version/sonar-scanner-cli-$scanner_version.jar" --output "$jar"
echo "$scanner_sha256  $jar" | sha256sum --check --status

version=$(scripts/release-notes.sh "$work_dir/release-notes.md")

java -jar "$jar" \
  -Dsonar.projectVersion="$version" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300
