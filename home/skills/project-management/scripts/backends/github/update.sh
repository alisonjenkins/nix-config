#!/usr/bin/env bash
# pm update <number> [--state open|done] [--label L] [--unlabel L] [--comment T] (github).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
set -- ${GH_REST[@]+"${GH_REST[@]}"}

num=""
state=""
comment=""
add=()
del=()
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --label)
      pm_arg2 "$@"
      add+=("$2")
      shift 2
      ;;
    --unlabel)
      pm_arg2 "$@"
      del+=("$2")
      shift 2
      ;;
    --comment)
      pm_arg2 "$@"
      comment="$2"
      shift 2
      ;;
    -*) pm_die "update: unsupported argument '$1'" ;;
    *)
      num="$1"
      shift
      ;;
  esac
done
[[ $num =~ ^[0-9]+$ ]] || pm_die "update: need an issue number"
case "$state" in
  "" | open | done) ;;
  *) pm_die "update: --state must be open or done" ;;
esac
if [[ -z $state && -z $comment && ${#add[@]} -eq 0 && ${#del[@]} -eq 0 ]]; then
  pm_die "update: nothing to do (give --state, --label, --unlabel or --comment)"
fi

pm_header github "repo=$GH_REPO"
did=()
report_partial() {
  if ((${#did[@]})); then
    echo "partially applied: ${did[*]}" >&2
  fi
}
trap report_partial ERR
if [[ -n $state ]]; then
  current="$(gh issue view "$num" -R "$GH_REPO" --json state | jq -r '.state')"
  if [[ $state == "done" && $current == OPEN ]]; then
    gh issue close "$num" -R "$GH_REPO" >/dev/null
    did+=("state=done")
  elif [[ $state == open && $current == CLOSED ]]; then
    gh issue reopen "$num" -R "$GH_REPO" >/dev/null
    did+=("state=open")
  fi
fi
for l in ${add[@]+"${add[@]}"}; do
  gh issue edit "$num" -R "$GH_REPO" --add-label "$l" >/dev/null
  did+=("+$l")
done
for l in ${del[@]+"${del[@]}"}; do
  gh issue edit "$num" -R "$GH_REPO" --remove-label "$l" >/dev/null
  did+=("-$l")
done
if [[ -n $comment ]]; then
  gh issue comment "$num" -R "$GH_REPO" --body "$comment" >/dev/null
  did+=("comment")
fi

if ((${#did[@]})); then
  echo "updated $num ${did[*]}"
else
  echo "unchanged $num"
fi
trap - ERR
