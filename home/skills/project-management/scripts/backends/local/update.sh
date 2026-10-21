#!/usr/bin/env bash
# pm update <id> --state open|done (local): flip the checkbox in tasks.md.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

local_take_dir "$@"
set -- ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}

id=""
want=""
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      want="$2"
      shift 2
      ;;
    -*) pm_die "update: unsupported argument '$1' for the local backend" ;;
    *)
      id="$1"
      shift
      ;;
  esac
done
[[ -n $id ]] || pm_die "update: need a task id"
[[ -n $want ]] || pm_die "update: --state is required for the local backend"
case "$want" in
  open | done) ;;
  *) pm_die "update: --state must be open or done" ;;
esac

current="$(tasks_md_tsv "$LOCAL_TASKS" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
[[ -n $current ]] || pm_die "no task $id in $LOCAL_TASKS"

pm_header local "dir=$LOCAL_DIR"
if [[ $current == "$want" ]]; then
  echo "unchanged $id state=$want"
else
  tasks_md_set_state "$LOCAL_TASKS" "$id" "$want" || pm_die "update: could not write $LOCAL_TASKS"
  echo "updated $id state=$want"
fi
