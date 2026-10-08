#!/usr/bin/env bash
# Runs every benchmark task against the ALREADY ACTIVE local profile.
# usage: run-bench.sh <label> <out-dir> [reps=2]
# env:   BENCH_DELEGATE  path to delegate-to-local-agent.sh (default: first on PATH, else the repo copy)
#        BENCH_TIMEOUT   per-run wall clock seconds (default 600)
#        BENCH_ONLY      space separated subset of task names (default all)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/common.sh
source "$here/lib/common.sh"

readonly DEFAULT_TIMEOUT_SECONDS=600
readonly DEFAULT_REPS=2
readonly KILL_GRACE_SECONDS=15
readonly OUTER_TIMEOUT_MARGIN_SECONDS=60
readonly REPO_DELEGATE_SUFFIX=git/personal/nix-config/home/skills/delegation/scripts/delegate-to-local-agent.sh

usage() {
  echo "usage: $0 <label> <out-dir> [reps=$DEFAULT_REPS]" >&2
  exit 1
}

find_delegate() {
  if [[ -n "${BENCH_DELEGATE:-}" ]]; then
    [[ -x "$BENCH_DELEGATE" ]] || die "BENCH_DELEGATE is not executable: $BENCH_DELEGATE"
    printf '%s\n' "$BENCH_DELEGATE"
    return
  fi
  if command -v delegate-to-local-agent.sh >/dev/null 2>&1; then
    command -v delegate-to-local-agent.sh
    return
  fi
  local candidate=$HOME/$REPO_DELEGATE_SUFFIX
  [[ -x "$candidate" ]] || die "delegate-to-local-agent.sh not found; set BENCH_DELEGATE"
  printf '%s\n' "$candidate"
}

now_ms() {
  date +%s%3N
}

[[ $# -ge 2 && $# -le 3 ]] || usage
label=$1
out=$(abs_dir "$2")
reps=${3:-$DEFAULT_REPS}
[[ "$reps" =~ ^[1-9][0-9]*$ ]] || die "reps must be a positive integer, got '$reps'"
timeout_s=${BENCH_TIMEOUT:-$DEFAULT_TIMEOUT_SECONDS}
[[ "$timeout_s" =~ ^[1-9][0-9]*$ ]] || die "BENCH_TIMEOUT must be a positive integer"

resolve_python
delegate=$(find_delegate)
read -r -a selected <<<"${BENCH_ONLY:-${BENCH_TASKS[*]}}"
is_edit_task() {
  local t
  for t in "${BENCH_TASKS_EDIT[@]}"; do
    [[ "$t" == "$1" ]] && return 0
  done
  return 1
}

mkdir -p "$out/work" "$out/logs"
results=$out/results.jsonl
: >"$results"
echo "bench '$label': delegate=$delegate reps=$reps timeout=${timeout_s}s out=$out" >&2

for task in "${selected[@]}"; do
  fixture=$here/fixtures/$task
  [[ -d "$fixture/input" ]] || die "unknown task '$task'"
  task_file=$fixture/task.txt
  task_text=$(<"$task_file")
  edit=0
  is_edit_task "$task" && edit=1
  run_timeout=$timeout_s
  [[ "$task" == boundaries ]] && run_timeout=${BENCH_BOUNDARIES_TIMEOUT:-240}

  for ((rep = 1; rep <= reps; rep++)); do
    run_id=$task-$rep
    work=$out/work/$run_id
    reply_file=$out/logs/$run_id.reply.txt
    stderr_file=$out/logs/$run_id.stderr.txt
    rm -rf -- "$work"
    fresh_copy "$fixture/input" "$work"
    work=$(cd "$work" && pwd -P)
    rm -f "$BOUNDARY_PROBE_FILE"

    echo "[$run_id] running (edit=$edit)" >&2
    started=$(now_ms)
    code=0
    LOCAL_LLM_AGENT_EDIT=$edit LOCAL_LLM_AGENT_TIMEOUT=$run_timeout \
      LOCAL_LLM_AGENT_LOG="$out/logs/$run_id.events.jsonl" \
      timeout --kill-after="$KILL_GRACE_SECONDS" "$((run_timeout + OUTER_TIMEOUT_MARGIN_SECONDS))" \
      "$delegate" "$work" "$task_text" >"$reply_file" 2>"$stderr_file" || code=$?
    finished=$(now_ms)

    grade_json=$("${PYTHON[@]}" "$fixture/grade.py" "$work" --reply-file "$reply_file") || grade_json=''
    rm -f "$BOUNDARY_PROBE_FILE"

    "${PYTHON[@]}" "$here/lib/record.py" \
      --results "$results" --label "$label" --task "$task" --rep "$rep" \
      --exit-code "$code" --millis "$((finished - started))" \
      --stderr-file "$stderr_file" --grade-json "$grade_json"
  done
done

"${PYTHON[@]}" "$here/lib/summarize.py" --results "$results" --label "$label" --out "$out/results.md"
echo "wrote $results and $out/results.md" >&2
