#!/usr/bin/env bash
# Keeps a PR's title/body as local files instead of round-tripping the
# whole body through a shell heredoc on every edit. `pull` fetches the
# current title and body once; edit the body file with the Edit tool
# (a small diff, not the full text) between rounds; `push` writes both
# back. Cuts the token cost of the "update the PR description to match
# what actually changed" step this skill's PR workflow otherwise repeats
# from scratch every review round.
set -euo pipefail

usage() {
  echo "usage: $0 <pull|push> <pr-number> [owner/repo]" >&2
  echo "  pull: writes the PR's current title and body to local files, prints their paths" >&2
  echo "  push: reads those files back and updates the PR's title and body" >&2
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

action="$1"
pr_number="$2"

case "$action" in
  pull | push) ;;
  *)
    usage
    exit 1
    ;;
esac

if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "error: <pr-number> must be numeric, got '$pr_number'" >&2
  exit 1
fi

repo_args=()
if [[ -n "${3:-}" ]]; then
  if ! [[ "$3" =~ ^[^/]+/[^/]+$ ]]; then
    echo "error: [owner/repo] must be exactly 'owner/repo', got '$3'" >&2
    exit 1
  fi
  repo_args=(-R "$3")
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

state_dir="$(git rev-parse --git-path "pr-description/$pr_number")"
mkdir -p "$state_dir"
title_file="$state_dir/title.txt"
body_file="$state_dir/body.md"

if [[ "$action" == "pull" ]]; then
  gh pr view "$pr_number" "${repo_args[@]}" --json title -q .title >"$title_file"
  gh pr view "$pr_number" "${repo_args[@]}" --json body -q .body >"$body_file"
  echo "title: $title_file"
  echo "body:  $body_file"
else
  if [[ ! -f "$title_file" || ! -f "$body_file" ]]; then
    echo "error: no pulled title/body found at $state_dir — run '$0 pull $pr_number' first" >&2
    exit 1
  fi
  gh pr edit "$pr_number" "${repo_args[@]}" --title "$(cat "$title_file")" --body-file "$body_file"
  echo "pushed title + body to PR #$pr_number"
fi
