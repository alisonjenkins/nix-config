#!/usr/bin/env bash
# pm show <number> [--full] (github): one issue as key<TAB>value lines.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

readonly BODY_LINES=20

gh_take_repo "$@"
full=0
num=""
for a in ${GH_REST[@]+"${GH_REST[@]}"}; do
  case "$a" in
    --full) full=1 ;;
    -*) pm_die "show: unsupported argument '$a'" ;;
    *) num="$a" ;;
  esac
done
[[ $num =~ ^[0-9]+$ ]] || pm_die "show: need an issue number"

json="$(gh issue view "$num" -R "$GH_REPO" --json "$GH_FIELDS,url")"

pm_header github "repo=$GH_REPO"
jq -c '[.]' <<<"$json" | jq -r -f "$script_dir/rows.jq" | pm_row_to_kv
jq -r '"url\t\(.url)\nupdated\t\(.updatedAt)"' <<<"$json"
echo "body"
body="$(jq -r '.body // ""' <<<"$json")"
if ((full)); then
  printf '%s\n' "$body"
else
  printf '%s\n' "$body" | awk -v n="$BODY_LINES" 'NR <= n'
  total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  if ((total > BODY_LINES)); then
    echo "... truncated ($total lines); use --full"
  fi
fi
