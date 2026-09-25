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

@test "acquire_lock never lets two holders in at once" {
  # A holder that had created the lock but not yet recorded its pid was
  # taken for dead and its lock deleted, so two callers ran the critical
  # section together: the delegate concurrency test failed 11 of 50 runs.
  local lock="$BATS_TEST_TMPDIR/counter.lock" counter="$BATS_TEST_TMPDIR/counter"
  echo 0 >"$counter"
  local pids=() i
  for i in $(seq 1 20); do
    bash -c '
      source "$1"
      for _ in 1 2 3 4 5; do
        acquire_lock "$2" 30 0.01 || exit 9
        n=$(<"$3"); sleep 0.002; echo $((n + 1)) >"$3"
        rm -rf "$2"
      done
    ' _ "$script_dir/../lib/queue-common.sh" "$lock" "$counter" 2>>"$BATS_TEST_TMPDIR/stderr" &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i"; done
  [ "$(<"$counter")" -eq 100 ]
  [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "acquire_lock takes over a lock whose holder has died" {
  local lock="$BATS_TEST_TMPDIR/dead.lock"
  bash -c 'source "$1"; acquire_lock "$2" 1' _ "$script_dir/../lib/queue-common.sh" "$lock"
  run acquire_lock "$lock" 1 0.05
  [ "$status" -eq 0 ]
}

@test "acquire_lock replaces an old-style directory lock rather than linking inside it" {
  # `ln -s pid dir` succeeds by creating the link inside the directory, so
  # a directory left by the previous lock format would let everyone in.
  local lock="$BATS_TEST_TMPDIR/old.lock"
  mkdir "$lock"
  acquire_lock "$lock" 1 0.05
  [ -L "$lock" ]
  [ "$(readlink "$lock")" = "$$" ]
}

@test "acquire_lock replaces a plain file at the lock path instead of spinning" {
  # ln fails on it and readlink reads nothing, which looped with no sleep
  # and no timeout check.
  local lock="$BATS_TEST_TMPDIR/file.lock"
  touch "$lock"
  run timeout 5 bash -c 'source "$1"; acquire_lock "$2" 1 0.05' _ "$script_dir/../lib/queue-common.sh" "$lock"
  [ "$status" -eq 0 ]
  [ -L "$lock" ]
}

@test "acquire_lock gives up on a lock a live process holds" {
  local lock="$BATS_TEST_TMPDIR/held.lock"
  bash -c 'source "$1"; acquire_lock "$2" 1; exec sleep 5' _ "$script_dir/../lib/queue-common.sh" "$lock" 3>&- &
  local holder=$!
  local _
  for _ in $(seq 1 50); do [[ -e "$lock" || -L "$lock" ]] && break; sleep 0.02; done
  run acquire_lock "$lock" 0.3 0.05
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 1 ]
}
