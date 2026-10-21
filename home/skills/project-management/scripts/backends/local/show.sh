#!/usr/bin/env bash
# pm show <id> (local): one task as key<TAB>value lines.
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
id=""
for a in ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}; do
  case "$a" in
    --full) ;; # the local backend has no long bodies
    -*) pm_die "show: unsupported argument '$a' for the local backend" ;;
    *) id="$a" ;;
  esac
done
[[ -n $id ]] || pm_die "show: need a task id"

row="$(tasks_md_tsv "$LOCAL_TASKS" | awk -F'\t' -v id="$id" '$1 == id')"
[[ -n $row ]] || pm_die "no task $id in $LOCAL_TASKS"

pm_header local "dir=$LOCAL_DIR"
printf '%s\n' "$row" | pm_row_to_kv
