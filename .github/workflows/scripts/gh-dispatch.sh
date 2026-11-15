#!/usr/bin/env bash
# Starts a GitHub Actions workflow through workflow_dispatch. Runs on the
# hypervisor (prox1) from a systemd timer, for workflows whose own
# `schedule:` GitHub starts late or not at all.
#
# Usage: gh-dispatch.sh <owner/repo> <workflow file> [ref]
#   e.g. gh-dispatch.sh community-scripts/DevScripts telemetry-issue-stats.yml
#
# Token: DISPATCH_TOKEN_FILE (default /etc/ci-controller/dispatch-token), a
# fine-grained token for that repository with Actions: read and write only.
# Kept apart from the runner token, which has Administration: write.

set -euo pipefail

REPO=${1:?usage: gh-dispatch.sh <owner/repo> <workflow file> [ref]}
WORKFLOW=${2:?usage: gh-dispatch.sh <owner/repo> <workflow file> [ref]}
REF=${3:-main}
TOKEN_FILE=${DISPATCH_TOKEN_FILE:-/etc/ci-controller/dispatch-token}

[[ -s "$TOKEN_FILE" ]] || { echo "no token in $TOKEN_FILE" >&2; exit 1; }

out=$(mktemp)
trap 'rm -f "$out"' EXIT
# The token goes in through stdin (--config -), never on the command line,
# where any local user could read it from the process list.
status=$(printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '\r\n' <"$TOKEN_FILE")" |
  curl -sS --config - -o "$out" -w '%{http_code}' -X POST \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  -d "$(jq -nc --arg r "$REF" '{ref: $r}')" \
  "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW/dispatches") || status=000

if [[ "$status" == 204 || "$status" == 200 ]]; then
  echo "$REPO: $WORKFLOW dispatched on $REF"
else
  echo "$REPO: dispatching $WORKFLOW failed ($status): $(jq -r '.message // empty' "$out" 2>/dev/null)" >&2
  exit 1
fi
