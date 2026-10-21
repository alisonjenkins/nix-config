#!/usr/bin/env bash
# pm status (local): counts, blocked and the next task to pick up.
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
((${#LOCAL_REST[@]} == 0)) || pm_die "status: unexpected argument '${LOCAL_REST[0]}'"

pm_header local "dir=$LOCAL_DIR"
tasks_md_tsv "$LOCAL_TASKS" | pm_status_from_tsv "n/a"
