#!/usr/bin/env bash
# Follows the open nightly flake-update PRs until they merge, so the nightly
# job (update.yaml) can open its PR and exit instead of waiting on the
# self-hosted runner. Run by .github/workflows/update-shepherd.yaml.
#
# `update-policy shepherd` (pkgs/update-policy/src/shepherd.rs) makes every
# decision; this script only fetches the PRs and acts on its lines:
#   rebase N         the PR is behind main: update its branch, checks re-run
#   stuck N reason   a human should look: open or update one tracking issue
#   wait N detail    nothing to do yet
#   missed reason    the nightly has not started for a day: also in the issue
# When nothing is stuck, the tracking issue is closed.
#
# Environment:
#   GH_TOKEN           updater App token: lists PRs and pushes rebases (its
#                      pushes start pull_request checks; GITHUB_TOKEN's do not)
#   ISSUE_TOKEN        token allowed to write issues (the workflow's GITHUB_TOKEN)
#   APP_SLUG           the updater App's slug, to find its PRs
#   GITHUB_REPOSITORY  owner/repo
#   RUN_URL            link to this run, put in the issue (optional)
#   UPDATE_POLICY      update-policy binary (default: update-policy on PATH)
#   STUCK_AFTER_HOURS  how long a PR may stay open before it is stuck (default 6)
#   REBASE_WINDOW      HH:MM-HH:MM UTC; rebases (which re-run checks on the home
#                      runner) only happen inside it (optional: always)
#
# Exit status: 0 when it ran (stuck PRs are reported through the issue, not by
# failing every half hour), non-zero when it could not run.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN (the updater App token) is not set}"
: "${ISSUE_TOKEN:?ISSUE_TOKEN (a token with issues: write) is not set}"
: "${APP_SLUG:?APP_SLUG (the updater App slug) is not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
UPDATE_POLICY="${UPDATE_POLICY:-update-policy}"
ISSUE_TITLE="Nightly flake update is stuck"
repo="$GITHUB_REPOSITORY"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! gh pr list --repo "$repo" --state open --author "app/$APP_SLUG" --limit 50 \
    --json number,headRefName,isDraft,createdAt,mergeStateStatus,statusCheckRollup \
    >"$work/prs.json" 2>"$work/err"; then
  echo "::error::could not list the updater App's open PRs: $(cat "$work/err")"
  exit 1
fi
window_args=()
if [ -n "${REBASE_WINDOW:-}" ]; then window_args=(--rebase-window "$REBASE_WINDOW"); fi

# When the nightly last started, so a missed night (timer, host or token
# broken) is reported too. Read with ISSUE_TOKEN: the App has no actions scope.
if ! last_nightly="$(GH_TOKEN="$ISSUE_TOKEN" gh api "repos/$repo/actions/workflows/update.yaml/runs?per_page=1" \
    --jq '.workflow_runs[0].created_at // "none"' 2>"$work/err")"; then
  echo "::error::could not read the nightly workflow's last run: $(cat "$work/err")"
  exit 1
fi

if ! "$UPDATE_POLICY" shepherd --prs "$work/prs.json" \
    --stuck-after-hours "${STUCK_AFTER_HOURS:-6}" "${window_args[@]}" \
    --last-nightly "$last_nightly" >"$work/decisions"; then
  echo "::error::update-policy shepherd failed; its message is above"
  exit 1
fi

stuck=()
while read -r verb number rest; do
  case "$verb" in
    rebase)
      if gh pr update-branch --repo "$repo" --rebase "$number" >/dev/null 2>"$work/err"; then
        echo "::notice::#$number was behind main; rebased it, so its checks run again"
      else
        reason="could not be rebased onto main ($(tr '\n' ' ' <"$work/err" | sed 's/ *$//')). The updater App has no workflows permission, so it cannot rebase in a main that changed a workflow; tomorrow's nightly replaces the PR, or press Update branch."
        echo "::warning::#$number $reason"
        stuck+=("#$number $reason")
      fi
      ;;
    stuck)
      echo "::warning::#$number $rest"
      stuck+=("#$number $rest")
      ;;
    wait)
      echo "#$number: $rest"
      ;;
    missed)
      echo "::warning::$number $rest"
      stuck+=("$number $rest")
      ;;
    *)
      echo "::error::update-policy shepherd printed a line this script does not understand: $verb $number $rest"
      exit 1
      ;;
  esac
done <"$work/decisions"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Nightly flake-update PRs"
    if [ -s "$work/decisions" ]; then sed 's/^/- /' "$work/decisions"; else echo "No open nightly PR."; fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

issues() { GH_TOKEN="$ISSUE_TOKEN" gh issue "$@" --repo "$repo"; }

if ! existing="$(issues list --state open --search "in:title \"$ISSUE_TITLE\"" --json number,title \
    --jq "map(select(.title == \"$ISSUE_TITLE\")) | .[0].number // empty" 2>"$work/err")"; then
  echo "::error::could not look for the tracking issue: $(cat "$work/err")"
  exit 1
fi

if [ "${#stuck[@]}" -eq 0 ]; then
  if [ -n "$existing" ]; then
    issues close "$existing" --comment "No nightly flake-update PR is stuck any more.${RUN_URL:+ Checked by $RUN_URL.}" >/dev/null
    echo "::notice::closed #$existing: nothing is stuck any more"
  fi
  exit 0
fi

{
  echo "The nightly flake update needs a look:"
  echo
  for line in "${stuck[@]}"; do echo "- $line"; done
  echo
  echo "Last checked $(date -u +%Y-%m-%dT%H:%M:%SZ)${RUN_URL:+ by $RUN_URL}. This issue is updated in place while the problem lasts and closed automatically once no nightly PR is stuck."
  echo "How the nightly update works: \`docs/update-policy.md\` (Flake inputs) and \`.github/workflows/update-shepherd.yaml\`."
} >"$work/body.md"

if [ -n "$existing" ]; then
  issues edit "$existing" --body-file "$work/body.md" >/dev/null
  echo "::notice::updated #$existing"
else
  url="$(issues create --title "$ISSUE_TITLE" --body-file "$work/body.md")"
  echo "::notice::opened $url"
fi
