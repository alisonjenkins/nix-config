#!/usr/bin/env bash
# Rebases the current branch onto the repo's default branch, the sequence
# this skill's PR workflow otherwise spells out by hand every time:
# detect the default branch, fetch it, rebase, and report what happened
# (including commits git silently drops as already-applied -- e.g. after
# the PR that introduced them already merged). Optionally re-pushes.
set -euo pipefail

usage() {
  echo "usage: $0 [--push]" >&2
  echo "  --push  force-with-lease push the current branch after a clean rebase" >&2
}

push=0
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    *)
      usage
      exit 1
      ;;
  esac
done

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

# Prefer the locally-recorded default branch (no network); fall back to
# probing common names as they exist on origin.
default_branch="$(detect_default_branch || true)"

if [[ -z "$default_branch" ]]; then
  echo "error: couldn't determine the default branch (no origin/HEAD, no main/master/trunk on origin)" >&2
  echo "  fix: git remote set-head origin --auto" >&2
  exit 1
fi

if [[ "$current_branch" == "$default_branch" ]]; then
  echo "error: already on the default branch ($default_branch); nothing to rebase onto itself" >&2
  exit 1
fi

echo "== rebasing $current_branch onto origin/$default_branch =="

if ! git fetch origin "$default_branch" 2>&1; then
  echo "error: git fetch origin $default_branch failed" >&2
  exit 1
fi

before_count="$(git rev-list --count "origin/$default_branch..HEAD")"

rebase_output="$(git rebase "origin/$default_branch" 2>&1)" && rebase_status=0 || rebase_status=$?
echo "$rebase_output"

if [[ $rebase_status -ne 0 ]]; then
  if rebase_dir="$(git rev-parse -q --git-path rebase-merge 2>/dev/null)" && [[ -d "$rebase_dir" ]]; then
    echo "error: rebase stopped, likely on a conflict — resolve it, then 'git rebase --continue'" >&2
    echo "  (or 'git rebase --abort' to give up and go back to before this ran)" >&2
  elif rebase_dir="$(git rev-parse -q --git-path rebase-apply 2>/dev/null)" && [[ -d "$rebase_dir" ]]; then
    echo "error: rebase stopped, likely on a conflict — resolve it, then 'git rebase --continue'" >&2
    echo "  (or 'git rebase --abort' to give up and go back to before this ran)" >&2
  else
    echo "error: git rebase failed before starting (see the output above) — no rebase is in progress, so there's nothing to --continue or --abort" >&2
  fi
  exit 1
fi

dropped="$(grep -c '^warning: skipped previously applied commit' <<<"$rebase_output" || true)"
after_count="$(git rev-list --count "origin/$default_branch..HEAD")"

echo "== done: $after_count commit(s) ahead of origin/$default_branch (was $before_count)"
if [[ "$dropped" -gt 0 ]]; then
  echo "   $dropped commit(s) dropped as already applied upstream (equivalent content already merged)"
fi

if [[ "$(git config --get commit.gpgsign || echo false)" == "true" ]]; then
  if ! "$script_dir/verify-signed.sh" "origin/$default_branch..HEAD"; then
    echo "warning: rebase produced unsigned commit(s) despite commit.gpgsign=true — see commit-messages.md's 'Preserving signatures'" >&2
  fi
fi

if [[ $push -eq 1 ]]; then
  echo "== pushing =="
  git push --force-with-lease origin "$current_branch"
fi
