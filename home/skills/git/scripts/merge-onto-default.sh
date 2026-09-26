#!/usr/bin/env bash
# Lands the current branch on the default branch by rebasing locally and
# pushing directly (a true fast-forward, no new commit objects), instead
# of `gh pr merge --rebase` -- which is a server-side operation that
# builds new commits GitHub has no way to sign with the user's key, so
# they land unsigned regardless of whether the source commits were
# signed (see commit-messages.md's "Preserving signatures"). Falls back
# to reporting that gap plainly, rather than silently accepting it, when
# the direct push is rejected (e.g. branch protection requires a PR).
#
# Requires an open PR for the branch: a default branch with required
# status checks enforces them on direct pushes too, so this gates on the
# PR's checks first via `gh pr checks --watch` (whatever checks the repo
# actually has — none assumed).
#
# `--watch` blocks until CI settles, often several minutes — run this in
# the background or with a raised timeout.
set -euo pipefail

usage() {
  echo "usage: $0" >&2
  echo "  rebases the current branch onto origin's default branch, then" >&2
  echo "  pushes it directly there (fast-forward, preserves signatures)." >&2
}

if [[ $# -ne 0 ]]; then
  usage
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

current_branch="$(git symbolic-ref --short -q HEAD || true)"
if [[ -z "$current_branch" ]]; then
  echo "error: not on a branch (detached HEAD)" >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "error: no 'origin' remote configured" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/default-branch.sh
source "$script_dir/lib/default-branch.sh"

default_branch="$(detect_default_branch || true)"
if [[ -z "$default_branch" ]]; then
  echo "error: couldn't determine the default branch (no origin/HEAD, no main/master/trunk on origin)" >&2
  exit 1
fi

if [[ "$current_branch" == "$default_branch" ]]; then
  echo "error: already on the default branch ($default_branch); nothing to merge" >&2
  exit 1
fi

if ! "$script_dir/rebase-onto-default.sh"; then
  echo "error: rebase failed — resolve it before merging (see above)" >&2
  exit 1
fi

if [[ "$(git config --get commit.gpgsign || echo false)" == "true" ]]; then
  if ! "$script_dir/verify-signed.sh" "origin/$default_branch..HEAD"; then
    echo "error: refusing to merge — commit(s) ahead of $default_branch are unsigned (see above)" >&2
    exit 1
  fi
fi

# stderr kept separate from stdout: mixing them into pr_info would break
# the TSV parse below on any warning, and could turn a transient `gh`
# error into a false "no PR" read that then force-pushes unexpectedly.
if ! pr_info="$(gh pr view --json number,headRefOid --jq '[.number,.headRefOid]|@tsv' 2>/dev/null)" || [[ -z "$pr_info" ]]; then
  echo "error: no open PR found for $current_branch, or 'gh pr view' failed — open one first" >&2
  echo "  (this script gates the direct push on that PR's checks; without one there's nothing to gate on)" >&2
  gh pr view --json number,headRefOid >&2 2>&1 || true
  exit 1
fi
IFS=$'\t' read -r pr_number pr_head_sha <<<"$pr_info"

local_head_sha="$(git rev-parse HEAD)"
if [[ "$local_head_sha" != "$pr_head_sha" ]]; then
  echo "== rebase moved HEAD — pushing $current_branch to update PR #$pr_number before checking CI =="
  git push --force-with-lease origin "$current_branch"
fi

# GitHub registers a push's checks asynchronously, so right after a push
# `gh pr checks` can report none, or the previous head's. Only "nothing
# registered on this exact SHA after a grace period" means the repo has no
# checks; a required check slower than that is still caught by branch
# protection rejecting the push below.
checks_register_timeout="${MERGE_ONTO_DEFAULT_CHECKS_REGISTER_TIMEOUT:-120}"
checks_register_interval="${MERGE_ONTO_DEFAULT_CHECKS_REGISTER_INTERVAL:-5}"

count_head_checks() {
  local check_runs statuses
  check_runs="$(gh api "repos/{owner}/{repo}/commits/$1/check-runs" --jq .total_count)" || return 1
  statuses="$(gh api "repos/{owner}/{repo}/commits/$1/status" --jq .total_count)" || return 1
  echo $((check_runs + statuses))
}

echo "== waiting up to ${checks_register_timeout}s for checks to register on $local_head_sha =="
deadline=$((SECONDS + checks_register_timeout))
head_checks=""
while :; do
  if head_checks="$(count_head_checks "$local_head_sha")" && ((head_checks > 0)); then
    break
  fi
  if ((SECONDS >= deadline)); then
    break
  fi
  sleep "$checks_register_interval"
done

if [[ -z "$head_checks" ]]; then
  echo "error: refusing to push — couldn't query checks on $local_head_sha (see gh errors above)" >&2
  exit 1
fi

if ((head_checks == 0)); then
  echo "== no checks registered on $local_head_sha after ${checks_register_timeout}s — nothing to gate on, proceeding =="
else
  echo "== waiting for PR #$pr_number's checks =="
  if ! gh pr checks "$pr_number" --watch 2>&1; then
    echo "error: refusing to push — PR #$pr_number's checks did not all pass (see above)" >&2
    exit 1
  fi
fi

echo "== pushing $current_branch onto origin/$default_branch (fast-forward) =="
if push_output="$(git push origin "HEAD:$default_branch" 2>&1)"; then
  echo "$push_output"
  echo "== done: $current_branch is now on $default_branch, signatures intact"
  exit 0
fi

echo "$push_output" >&2
echo "error: direct push to $default_branch was rejected — likely branch protection requires merging via a pull request" >&2
echo "  fall back: 'gh pr merge <number> --rebase' will still work, but the resulting commit(s) on" >&2
echo "  $default_branch will be unsigned regardless of your local signing (see commit-messages.md)." >&2
echo "  Ask before doing that if signed history on $default_branch matters for this repo." >&2
exit 1
