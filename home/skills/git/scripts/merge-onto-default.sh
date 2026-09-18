#!/usr/bin/env bash
# Lands the current branch on the default branch by rebasing locally and
# pushing directly (a true fast-forward, no new commit objects), instead
# of `gh pr merge --rebase` -- which is a server-side operation that
# builds new commits GitHub has no way to sign with the user's key, so
# they land unsigned regardless of whether the source commits were
# signed (see commit-messages.md's "Preserving signatures"). Falls back
# to reporting that gap plainly, rather than silently accepting it, when
# the direct push is rejected (e.g. branch protection requires a PR).
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

echo "== rebasing $current_branch onto origin/$default_branch =="
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
