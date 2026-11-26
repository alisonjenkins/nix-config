#!/usr/bin/env bash
# Starts the nightly flake update (update.yaml) with a workflow_dispatch.
# Run at 02:00 UK time by the nightly-update-trigger systemd timer on the home
# builder (modules/nightly-update-trigger): GitHub's own cron started the
# 02:00 run 7-10 hours late, outside the 00:30-05:30 cheap-power window the
# home runners are kept to.
#
# Environment:
#   TOKEN_FILE  file holding a fine-grained token for REPO with
#               "Actions: read and write" only
#   REPO        owner/repo (default alisonjenkins/nix-config)
#   WORKFLOW    workflow file name (default update.yaml)
#   REF         branch to run on (default main)
#   API_URL     GitHub API base (default https://api.github.com; tests override)
#
# Exit status: 0 dispatched, 1 GitHub refused (the message says why), 2 could
# not run. A missed night is also reported by update-shepherd.yaml.
set -euo pipefail

: "${TOKEN_FILE:?TOKEN_FILE (path to the dispatch token) is not set}"
REPO="${REPO:-alisonjenkins/nix-config}"
WORKFLOW="${WORKFLOW:-update.yaml}"
REF="${REF:-main}"
API_URL="${API_URL:-https://api.github.com}"

if [ ! -r "$TOKEN_FILE" ]; then
  echo "nightly-dispatch: cannot read the token file $TOKEN_FILE" >&2
  exit 2
fi
token="$(tr -d '[:space:]' <"$TOKEN_FILE")"
if [ -z "$token" ]; then
  echo "nightly-dispatch: the token file $TOKEN_FILE is empty" >&2
  exit 2
fi

body="$(mktemp)"
trap 'rm -f "$body"' EXIT
url="$API_URL/repos/$REPO/actions/workflows/$WORKFLOW/dispatches"

# The token goes in through a config on stdin, so it never shows in argv.
if ! status="$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl --silent --show-error \
    --max-time 60 --retry 3 --retry-delay 10 --retry-all-errors \
    --config - \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --output "$body" --write-out '%{http_code}' \
    --request POST --data "{\"ref\":\"$REF\"}" "$url")"; then
  echo "nightly-dispatch: could not reach $API_URL (curl failed, see above)" >&2
  exit 2
fi

case "$status" in
  204)
    echo "nightly-dispatch: started $WORKFLOW on $REPO@$REF"
    exit 0
    ;;
  401)
    hint="the token is invalid or has expired; make a new one (see modules/nightly-update-trigger/default.nix)"
    ;;
  403)
    hint="the token lacks \"Actions: read and write\" on $REPO, or the workflow is disabled"
    ;;
  404)
    hint="$REPO or .github/workflows/$WORKFLOW was not found, or the token cannot see $REPO"
    ;;
  422)
    hint="GitHub rejected the request: does $WORKFLOW still have a workflow_dispatch trigger, and does branch $REF exist?"
    ;;
  *)
    hint="unexpected response"
    ;;
esac
echo "nightly-dispatch: GitHub answered HTTP $status: $hint" >&2
if [ -s "$body" ]; then
  echo "nightly-dispatch: response: $(head -c 500 "$body")" >&2
fi
exit 1
