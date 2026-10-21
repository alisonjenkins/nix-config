#!/usr/bin/env bash
# pm list (github): issue rows from one paged gh call.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
set -- ${GH_REST[@]+"${GH_REST[@]}"}

state=open
due_before=""
extra=()
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --label)
      pm_arg2 "$@"
      extra+=(--label "$2")
      shift 2
      ;;
    --milestone)
      pm_arg2 "$@"
      extra+=(--milestone "$2")
      shift 2
      ;;
    --assignee)
      pm_arg2 "$@"
      extra+=(--assignee "$2")
      shift 2
      ;;
    --due-before)
      pm_arg2 "$@"
      due_before="$2"
      shift 2
      ;;
    *) pm_die "list: unsupported argument '$1'" ;;
  esac
done
case "$state" in
  open) gh_state=open ;;
  done) gh_state=closed ;;
  all) gh_state=all ;;
  *) pm_die "list: --state must be open, done or all" ;;
esac

json="$(gh issue list -R "$GH_REPO" --state "$gh_state" --limit "$GH_LIMIT" --json "$GH_FIELDS" ${extra[@]+"${extra[@]}"})"
gh_warn_truncated "$json"

pm_header github "repo=$GH_REPO"
# The assignee filter is gh's (it resolves @me and matches any assignee), so it is not re-applied here.
jq -r -f "$script_dir/rows.jq" <<<"$json" | pm_filter_tsv "$state" "" "$due_before"
