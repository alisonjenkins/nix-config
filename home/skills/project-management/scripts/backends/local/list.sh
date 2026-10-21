#!/usr/bin/env bash
# pm list (local): task rows from tasks.md.
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

state=open
assignee=""
due_before=""
page_size=""
offset=0
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --assignee)
      pm_arg2 "$@"
      assignee="$2"
      shift 2
      ;;
    --due-before)
      pm_arg2 "$@"
      due_before="$2"
      shift 2
      ;;
    --limit)
      pm_arg2 "$@"
      page_size="$2"
      shift 2
      ;;
    --offset)
      pm_arg2 "$@"
      offset="$2"
      shift 2
      ;;
    *) pm_die "list: unsupported argument '$1' for the local backend" ;;
  esac
done
case "$state" in
  open | done | all) ;;
  *) pm_die "list: --state must be open, done or all" ;;
esac
pm_page_check "$page_size" "$offset"

pm_header local "dir=$LOCAL_DIR"
tasks_md_tsv "$LOCAL_TASKS" | pm_filter_tsv "$state" "$assignee" "$due_before" | pm_page "$page_size" "$offset"
