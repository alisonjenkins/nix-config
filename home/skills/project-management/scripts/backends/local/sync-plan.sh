#!/usr/bin/env bash
# pm sync-plan <file> [--apply] (local): add task lines from <file> to
# tasks.md when their id is absent. Dry run unless --apply.
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

LOCAL_TASKS_OPTIONAL=1
local_take_dir "$@"
set -- ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}

apply=0
file=""
while (($#)); do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    -*) pm_die "sync-plan: unsupported argument '$1' for the local backend" ;;
    *)
      [[ -z $file ]] || pm_die "sync-plan: takes one file"
      file="$1"
      shift
      ;;
  esac
done
[[ -n $file && -f $file ]] || pm_die "sync-plan: need an existing plan file"

existing=""
if [[ -f $LOCAL_TASKS ]]; then
  existing="$(tasks_md_tsv "$LOCAL_TASKS" | cut -f1)"
fi
# Space-delimited id list. Ids never contain spaces, a case match avoids a pipe
# (grep -q under pipefail can fail on SIGPIPE), and ids created earlier in this
# run are added to it, so a duplicate id in the plan is created only once.
seen=" $(printf '%s' "$existing" | tr '\n' ' ') "

pm_header local "dir=$LOCAL_DIR"
while IFS="$(printf '\t')" read -r id raw; do
  title="$(tasks_md_tsv <(printf '%s\n' "$raw") | cut -f3)"
  case "$seen" in
    *" $id "*) printf 'exists\ttask\t%s\t%s\n' "$id" "$title" ;;
    *)
      if ((apply)); then
        mkdir -p "$LOCAL_DIR"
        tasks_md_append "$LOCAL_TASKS" "$raw"
        printf 'created\ttask\t%s\t%s\n' "$id" "$title"
      else
        printf 'would-create\ttask\t%s\t%s\n' "$id" "$title"
      fi
      seen="$seen$id "
      ;;
  esac
done < <(tasks_md_raw "$file")
