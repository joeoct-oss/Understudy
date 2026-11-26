#!/usr/bin/env bash
#
#  post-security-alerts.sh
#  Understudy
#
#  Created by Yousef Mohamed <youseef.elserwey@gmail.com>.
#  Copyright © 2026 Yousef Mohamed. MIT License.
#

# Posts the code scanning and secret scanning alerts opened since the Security alerts workflow's
# last successful run on main to a Slack incoming webhook, as one message. Posts nothing when no
# alert is new. The first run, with no successful run before it, posts every open alert. A secret
# scanning alert shows only the kind of secret and a link, never the secret itself.
# - Each run covers the alerts created from the start of the last successful run up to its own
#   start, so no alert is posted twice and none is missed when a scheduled run is late or fails.
# - Code scanning is read with GH_TOKEN. GitHub's workflow token can't read secret scanning
#   alerts, so those are read with SECRET_SCANNING_TOKEN, a token that can.
# - Fails when either kind of alert can't be read or Slack refuses the message, so a broken feed
#   shows as a failed run instead of a quiet channel.
# With --dry-run it prints the message instead of posting it, and needs no webhook.
#
# Usage: [--dry-run] scripts/post-security-alerts.sh
# Environment: GITHUB_REPOSITORY (owner/name), GH_TOKEN, SECRET_SCANNING_TOKEN,
#   SLACK_WEBHOOK_URL (not with --dry-run), GITHUB_RUN_ID (in the workflow; else now is the end)

set -euo pipefail

workflow_file="security-alerts.yml"
max_lines=20
dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
fi

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be owner/name}"
: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${SECRET_SCANNING_TOKEN:?SECRET_SCANNING_TOKEN must be set, as the workflow token cannot read secret scanning}"
if [[ "$dry_run" == false ]]; then
    : "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL must be set}"
fi

# The window: from the start of the last successful run on main to the start of this run.
since=$(gh api "repos/$repo/actions/workflows/$workflow_file/runs?branch=main&status=success&per_page=1" \
    --jq '.workflow_runs[0].created_at // ""')
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
    until=$(gh api "repos/$repo/actions/runs/$GITHUB_RUN_ID" --jq '.created_at')
else
    until=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

# Timestamps are all UTC ISO 8601 with a Z, so comparing them as strings orders them in time.
# Slack's own markup characters are escaped in every text that comes from an alert.
code_lines=$(gh api --paginate "repos/$repo/code-scanning/alerts?state=open&per_page=100" \
    --jq '.[] | @json' |
    jq -r --arg since "$since" --arg until "$until" '
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        select(.created_at >= $since and .created_at < $until)
        | (.rule.security_severity_level // .rule.severity // "unknown") as $level
        | (.most_recent_instance.location // {}) as $where
        | "• Code scanning, \($level): <\(.html_url)|\((.rule.description // .rule.id // "alert") | esc)>"
          + (if $where.path then " in `\($where.path | esc):\($where.start_line // 1)`" else "" end)')

secret_lines=$(GH_TOKEN="$SECRET_SCANNING_TOKEN" gh api --paginate \
    "repos/$repo/secret-scanning/alerts?state=open&per_page=100" --jq '.[] | @json' |
    jq -r --arg since "$since" --arg until "$until" '
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        select(.created_at >= $since and .created_at < $until)
        | "• Secret scanning: <\(.html_url)|\((.secret_type_display_name // .secret_type // "secret") | esc)>"')

lines=$(printf '%s\n%s\n' "$code_lines" "$secret_lines" | sed '/^$/d')
if [[ -z "$lines" ]]; then
    echo "No new code scanning or secret scanning alerts in $repo between ${since:-the start} and $until."
    exit 0
fi

count=$(printf '%s\n' "$lines" | wc -l | tr -d ' ')
noun="alerts"
if [[ "$count" -eq 1 ]]; then
    noun="alert"
fi
header="*$repo: $count new security $noun*"
if [[ -z "$since" ]]; then
    header="*$repo: $count open security $noun* (first run, so every open alert)"
fi
# sed reads every line before it stops, so the pipe never closes early on a long list.
body=$(printf '%s\n' "$lines" | sed -n "1,${max_lines}p")
if [[ "$count" -gt "$max_lines" ]]; then
    body+=$'\n'"…and $((count - max_lines)) more: <https://github.com/$repo/security|Security tab>"
fi
payload=$(jq -n --arg text "$header"$'\n'"$body" '{text: $text}')

if [[ "$dry_run" == true ]]; then
    echo "$payload"
    exit 0
fi

response=$(curl --silent --show-error --fail-with-body --max-time 30 \
    -H 'Content-Type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL")
if [[ "$response" != "ok" ]]; then
    echo "error: Slack refused the message: $response" >&2
    exit 1
fi
echo "Posted $count $noun to Slack."
