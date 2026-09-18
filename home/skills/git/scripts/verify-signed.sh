#!/usr/bin/env bash
# Checks every commit in a rev-range for a valid-looking signature (a
# gpgsig/gpgsig-sha256 header on the raw object). Exists because some
# operations (filter-branch, filter-repo) silently drop signatures even
# with signing configured -- see commit-messages.md's "Preserving
# signatures". Presence-only check: it does not verify the signature is
# cryptographically valid, only that one was attached at commit time.
set -euo pipefail

usage() {
  echo "usage: $0 <rev-range>" >&2
  echo "  e.g. $0 origin/main..HEAD" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

range="$1"

if ! commits="$(git rev-list "$range" -- 2>&1)"; then
  echo "error: not a valid rev-range: $range" >&2
  echo "$commits" >&2
  exit 1
fi

if [[ -z "$commits" ]]; then
  echo "(no commits in range)"
  exit 0
fi

unsigned=0
while IFS= read -r sha; do
  subject="$(git log -1 --format='%s' "$sha")"
  if git cat-file -p "$sha" | grep -q '^gpgsig'; then
    echo "SIGNED   $sha $subject"
  else
    echo "UNSIGNED $sha $subject"
    unsigned=$((unsigned + 1))
  fi
done <<<"$commits"

if [[ $unsigned -gt 0 ]]; then
  echo "error: $unsigned commit(s) unsigned" >&2
  exit 1
fi
