# shellcheck shell=bash
# Shared argument handling for the local backend verbs. Sourced.

# local_take_dir "$@": take -d/--dir out of the arguments.
# Sets LOCAL_DIR, LOCAL_TASKS and LOCAL_REST (the other arguments).
local_take_dir() {
  LOCAL_DIR="${PM_DIR:-}"
  LOCAL_REST=()
  while (($#)); do
    case "$1" in
      -d | --dir)
        pm_arg2 "$@"
        LOCAL_DIR="$2"
        shift 2
        ;;
      --dir=*)
        LOCAL_DIR="${1#--dir=}"
        shift
        ;;
      *)
        LOCAL_REST+=("$1")
        shift
        ;;
    esac
  done
  [[ -n $LOCAL_DIR ]] || pm_die "the local backend needs -d <dir> (the directory holding tasks.md)"
  LOCAL_TASKS="$LOCAL_DIR/tasks.md"
  if [[ ${LOCAL_TASKS_OPTIONAL:-0} != 1 && ! -f $LOCAL_TASKS ]]; then
    pm_die "no tasks.md in $LOCAL_DIR"
  fi
}
