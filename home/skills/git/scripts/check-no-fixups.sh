#!/usr/bin/env bash
# Fails if any commit in a rev-range has a `fixup!`, `squash!` or `amend!`
# subject -- the markers `git commit --fixup/--squash` writes and
# `rebase --autosquash` consumes. The PR workflow keeps fixups as visible
# commits while a PR is open, so nothing stops one reaching the default
# branch except this check; merge-onto-default.sh runs it first, and it
# must be run by hand before any `gh pr merge` fallback, which has no
# such gate.
set -euo pipefail

usage() {
  echo "usage: $0 [rev-range]" >&2
  echo "  default range: origin/<default branch>..HEAD" >&2
}

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  range="$1"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/default-branch.sh
  source "$script_dir/lib/default-branch.sh"
  default_branch="$(detect_default_branch || true)"
  if [[ -z "$default_branch" ]]; then
    echo "error: couldn't determine the default branch; pass a rev-range" >&2
    exit 1
  fi
  range="origin/$default_branch..HEAD"
fi

if ! subjects="$(git log --format='%h %s' "$range" -- 2>&1)"; then
  echo "error: not a valid rev-range: $range" >&2
  echo "$subjects" >&2
  exit 1
fi

markers="$(grep -E '^[0-9a-f]+ (fixup|squash|amend)! ' <<<"$subjects" || true)"
if [[ -z "$markers" ]]; then
  echo "(no fixup!/squash!/amend! commits in $range)"
  exit 0
fi

echo "$markers" >&2
echo "error: $(wc -l <<<"$markers") fixup/squash/amend commit(s) in $range -- fold them into their targets before merging:" >&2
echo "  GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <default branch remote ref>" >&2
echo "  then force-with-lease push the PR branch and re-run" >&2
exit 1
