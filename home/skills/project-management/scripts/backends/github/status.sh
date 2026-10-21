#!/usr/bin/env bash
# pm status (github): counts, stale (open, untouched for 14 days), blocked, next.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
((${#GH_REST[@]} == 0)) || pm_die "status: unexpected argument '${GH_REST[0]}'"

json="$(gh issue list -R "$GH_REPO" --state all --limit "$GH_LIMIT" --json "$GH_FIELDS")"
gh_warn_truncated "$json"
stale="$(jq -r '[.[] | select(.state == "OPEN" and .updatedAt < (now - 1209600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | length' <<<"$json")"

pm_header github "repo=$GH_REPO"
jq -r -f "$script_dir/rows.jq" <<<"$json" | pm_status_from_tsv "$stale"
