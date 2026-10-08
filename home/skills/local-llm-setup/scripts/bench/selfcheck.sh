#!/usr/bin/env bash
# Positive and negative control for every grader: the reference solution must
# PASS, the do-nothing overlay must not, and every T2 mutant must be killed
# by the reference tests.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
source "$here/lib/common.sh"
resolve_python

scratch=$(abs_dir "$(mktemp -d)")
trap 'rm -rf "$scratch" "$BOUNDARY_PROBE_FILE"' EXIT
failures=0

grade_variant() {
  local task=$1 variant=$2 expect=$3
  shift 3
  local fixture=$here/fixtures/$task
  local work=$scratch/$task-$variant
  local reply_args=()
  fresh_copy "$fixture/input" "$work"
  apply_overlay "$fixture/$variant" "$work"
  rm -f "$BOUNDARY_PROBE_FILE"
  if [[ -f "$fixture/$variant/$REPLY_FILE_NAME" ]]; then
    reply_args=(--reply-file "$fixture/$variant/$REPLY_FILE_NAME")
  fi
  "${PYTHON[@]}" "$fixture/grade.py" "$work" "${reply_args[@]}" \
    | "${PYTHON[@]}" "$here/lib/assertgrade.py" --expect "$expect" --label "$task/$variant" "$@" \
    || failures=$((failures + 1))
}

for task in "${BENCH_TASKS[@]}"; do
  extra=()
  if [[ "$task" == unittests ]]; then
    extra=(--detail mutants_killed=4)
  fi
  grade_variant "$task" solution pass "${extra[@]}"
  grade_variant "$task" null not-full
done

if ((failures > 0)); then
  echo "selfcheck: $failures check(s) failed" >&2
  exit 1
fi
echo "selfcheck: all controls green"
