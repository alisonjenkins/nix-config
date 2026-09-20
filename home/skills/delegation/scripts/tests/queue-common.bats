#!/usr/bin/env bats
# Unit tests for lib/queue-common.sh's own functions, sourced directly —
# unlike queue-worker.sh, this file has no side effects on source, so it
# can be tested without going through a full switch/chat/stop job.

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  # shellcheck source=../lib/queue-common.sh
  source "$script_dir/../lib/queue-common.sh"
  results_dir="$BATS_TEST_TMPDIR/results"
  mkdir -p "$results_dir"
}

@test "sweep_stale_results deletes a result older than the max age" {
  touch "$results_dir/old.result"
  touch -d "@$(($(date +%s) - 3600))" "$results_dir/old.result"
  LOCAL_LLM_RESULT_MAX_AGE_SECONDS=60 sweep_stale_results "$BATS_TEST_TMPDIR"
  [ ! -e "$results_dir/old.result" ]
}

@test "sweep_stale_results leaves a fresh result alone" {
  touch "$results_dir/fresh.result"
  LOCAL_LLM_RESULT_MAX_AGE_SECONDS=1800 sweep_stale_results "$BATS_TEST_TMPDIR"
  [ -e "$results_dir/fresh.result" ]
}

@test "sweep_stale_results is a no-op on an empty results dir" {
  run sweep_stale_results "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "sweep_stale_results ignores a results dir that doesn't exist yet" {
  run sweep_stale_results "$BATS_TEST_TMPDIR/nothing-here"
  [ "$status" -eq 0 ]
}
