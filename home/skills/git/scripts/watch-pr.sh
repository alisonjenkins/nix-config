#!/usr/bin/env bash
# Unattended PR watch loop: keeps the current branch rebased onto the
# default branch and polls for review activity, all in plain bash -- no
# model turn spent per tick. Exits (waking whoever launched it) only on
# real activity, a rebase problem needing judgement, or prolonged idle.
# Run this via `run_in_background` or a Monitor, not a per-tick
# ScheduleWakeup: each tick here costs a `git fetch` + a `gh pr view`
# call, not an LLM turn, which is the whole point.
#
# Needs exclusive use of its checkout for its whole run: it rebases
# whatever branch is currently checked out, every tick, so switching that
# checkout to another branch while this is running (in the same worktree)
# makes the next tick rebase the wrong branch and fail with
# NEEDS_ATTENTION. Give it its own worktree if the main session needs to
# keep working elsewhere while this watches.
#
# Triage current feedback (scripts/pr-status.sh) BEFORE starting this,
# not after: whatever review state exists on tick 1 becomes the known
# baseline, silently, since there's nothing yet to compare it against.
# Feedback already sitting on the PR when you start watching is not
# reported -- only a change from that baseline is. To close the seconds-wide
# window between triage and this first tick, pass the review count you
# triaged in WATCH_PR_TRIAGED_REVIEWS (gh pr view N --json reviews -q
# '.reviews|length'); a different count on tick 1 wakes you immediately.
set -euo pipefail

usage() {
  echo "usage: $0 <pr-number> [owner/repo]" >&2
  echo "  loops until real PR activity, a rebase problem, or idle timeout" >&2
  echo "  prints one of NEW_ACTIVITY / NEEDS_ATTENTION / PR_CLOSED / PR_MERGED /" >&2
  echo "  IDLE_TIMEOUT and exits" >&2
  echo "  env: WATCH_PR_START_INTERVAL (default 60s), WATCH_PR_MAX_INTERVAL" >&2
  echo "       (default 900s), WATCH_PR_RATIO (default 1.5), WATCH_PR_MAX_SECONDS" >&2
  echo "       (default 86400 = 24h), WATCH_PR_TRIAGED_REVIEWS (review count seen at" >&2
  echo "       triage; a different count on tick 1 reports NEW_ACTIVITY)" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

pr_number="$1"
if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "error: <pr-number> must be numeric, got '$pr_number'" >&2
  exit 1
fi

repo_args=()
if [[ -n "${2:-}" ]]; then
  if ! [[ "$2" =~ ^[^/]+/[^/]+$ ]]; then
    echo "error: [owner/repo] must be exactly 'owner/repo', got '$2'" >&2
    exit 1
  fi
  repo_args=(-R "$2")
fi

numeric_env_or_default() {
  local var_name="$1" default_value="$2" value="${!1:-}"
  if [[ -z "$value" ]]; then
    echo "$default_value"
    return
  fi
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "warning: \$$var_name='$value' is not a non-negative integer; using $default_value" >&2
    echo "$default_value"
    return
  fi
  echo "$value"
}

human_duration() {
  local s=$1
  printf '%dh%02dm%02ds' "$((s / 3600))" "$(((s % 3600) / 60))" "$((s % 60))"
}

interval="$(numeric_env_or_default WATCH_PR_START_INTERVAL 60)"
max_interval="$(numeric_env_or_default WATCH_PR_MAX_INTERVAL 900)"
max_seconds="$(numeric_env_or_default WATCH_PR_MAX_SECONDS 86400)"
triaged_reviews="$(numeric_env_or_default WATCH_PR_TRIAGED_REVIEWS "")"
ratio="${WATCH_PR_RATIO:-1.5}"
if ! [[ "$ratio" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v r="$ratio" 'BEGIN { exit !(r >= 1) }'; then
  echo "warning: \$WATCH_PR_RATIO='$ratio' is not a number >= 1 (a smaller ratio would shrink the interval instead of backing off); using 1.5" >&2
  ratio=1.5
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

start_epoch="$(date +%s)"
prev_fingerprint=""

echo "== watching PR #$pr_number (start interval ${interval}s, cap ${max_interval}s, idle timeout $(human_duration "$max_seconds")) =="

while :; do
  # Keep rebased first, so any state change this causes (updatedAt,
  # reviewDecision reset on new commits) is baked into this tick's
  # fingerprint below rather than misread as external activity next tick.
  current_branch="$(git symbolic-ref --short -q HEAD || true)"
  if [[ -z "$current_branch" ]]; then
    echo "NEEDS_ATTENTION: detached HEAD, can't rebase or push"
    exit 1
  fi
  if ! rebase_out="$("$script_dir/rebase-onto-default.sh" --push 2>&1)"; then
    echo "NEEDS_ATTENTION: rebase-onto-default.sh failed, resolve before continuing:"
    echo "$rebase_out"
    exit 1
  fi

  gh_stderr="$(mktemp)"
  if ! fingerprint="$(gh pr view "$pr_number" "${repo_args[@]}" \
    --json state,reviewDecision,updatedAt,mergeable,mergeStateStatus,reviews \
    -q '[.state,(.reviewDecision // "null"),.updatedAt,.mergeable,.mergeStateStatus,(.reviews|length)] | @tsv' \
    2>"$gh_stderr")"; then
    echo "NEEDS_ATTENTION: gh pr view failed, resolve before continuing:"
    cat "$gh_stderr"
    rm -f "$gh_stderr"
    exit 1
  fi
  rm -f "$gh_stderr"

  pr_state="${fingerprint%%$'\t'*}"
  if [[ "$pr_state" == "CLOSED" || "$pr_state" == "MERGED" ]]; then
    echo "PR_${pr_state}: PR #$pr_number is $pr_state, nothing left to watch for"
    exit 0
  fi

  if [[ -z "$prev_fingerprint" && -n "$triaged_reviews" ]]; then
    # reviews is the last tsv column of the fingerprint query above
    current_reviews="${fingerprint##*$'\t'}"
    if [[ "$current_reviews" != "$triaged_reviews" ]]; then
      echo "NEW_ACTIVITY: review count changed since triage"
      echo "  triaged $triaged_reviews review(s), now $current_reviews: $fingerprint"
      exit 0
    fi
  fi

  if [[ -n "$prev_fingerprint" && "$fingerprint" != "$prev_fingerprint" ]]; then
    echo "NEW_ACTIVITY: PR state changed"
    echo "  before: $prev_fingerprint"
    echo "  after:  $fingerprint"
    exit 0
  fi
  prev_fingerprint="$fingerprint"

  now_epoch="$(date +%s)"
  if ((now_epoch - start_epoch >= max_seconds)); then
    echo "IDLE_TIMEOUT: no activity in $(human_duration "$max_seconds")"
    exit 0
  fi

  sleep "$interval"
  interval="$(awk -v i="$interval" -v r="$ratio" -v m="$max_interval" \
    'BEGIN {
      v = i * r
      v = (v == int(v)) ? v : int(v) + 1  # round up: truncating stalls the ramp (e.g. 1*1.5 -> 1)
      if (v > m) v = m
      printf "%d", v
    }')"
done
