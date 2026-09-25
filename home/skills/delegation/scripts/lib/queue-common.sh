#!/usr/bin/env bash
# Sourced by delegate-to-local.sh, switch-local-profile.sh,
# stop-local-profile.sh, and queue-worker.sh. The shebang above is only for
# editor/shellcheck tooling: this file is not meant to be executed directly,
# and inherits the sourcing script's `set` options.

# Deletes .result files older than LOCAL_LLM_RESULT_MAX_AGE_SECONDS
# (default 1800s) from $1/results. A caller that gives up waiting
# (submit_and_wait's own timeout) leaves its job's eventual result behind —
# nobody's left waiting on it, so nothing else would ever delete it
# otherwise. Uses stat's own mtime rather than `find -mmin` (minute
# granularity, awkward to test deterministically) for a plain integer
# seconds-since-epoch comparison.
sweep_stale_results() {
  local state_dir="$1" max_age_seconds now f mtime age
  max_age_seconds="$(numeric_env_or_default LOCAL_LLM_RESULT_MAX_AGE_SECONDS 1800)"
  max_age_seconds="${max_age_seconds%.*}"
  now="$(date +%s)"
  for f in "$state_dir/results"/*.result; do
    [[ -e "$f" ]] || continue
    mtime="$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null)" || continue
    age=$((now - mtime))
    # `|| true`: under `set -e`, a false `((...))` has exit status 1, which
    # would otherwise abort this whole function on the common case (a
    # fresh-enough file, nothing to delete) instead of just continuing the
    # loop — the same class of bug already fixed for active_reservation_for
    # and model_size_bytes's callers elsewhere in this file/queue-worker.sh.
    { ((age > max_age_seconds)) && rm -f "$f"; } || true
  done
}

numeric_env_or_default() {
  local var_name="$1" default_value="$2" value="${!1:-}"
  if [[ -z "$value" ]]; then
    printf '%s' "$default_value"
    return
  fi
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "warning: \$$var_name='$value' is not a non-negative number; using $default_value" >&2
    printf '%s' "$default_value"
    return
  fi
  printf '%s' "$value"
}

resolve_local_llm_state_dir() {
  if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
    echo "$LOCAL_LLM_STATE_DIR"
  elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    echo "$XDG_CACHE_HOME/delegate-to-local"
  elif [[ -n "${HOME:-}" ]]; then
    echo "$HOME/.cache/delegate-to-local"
  else
    return 1
  fi
}

# The lock is a symlink whose target is the holder's pid: `ln -s` creates
# it and records the owner in one atomic step, and portably (flock isn't on
# macOS by default). The previous mkdir-then-write-a-pid lock had a window
# with no pid in it, in which a waiter under load took a live holder's lock
# for abandoned and deleted it, letting two callers in. Used only for tiny
# critical sections (the job-sequence counter, electing a single worker
# starter), never held for the duration of actual model work — the queue
# worker's strictly-serial loop is what provides that exclusion.
acquire_lock() {
  local lock="$1" timeout="$2" interval="${3:-0.2}" elapsed=0 holder
  while true; do
    # Anything here but a symlink is not a lock of this format: a directory
    # is an old-style one, which `ln` would link inside and report success,
    # and a plain file would leave readlink nothing to read forever.
    if [[ -e "$lock" && ! -L "$lock" ]]; then
      rm -rf "$lock"
      continue
    fi
    if ln -s "$$" "$lock" 2>/dev/null; then
      return 0
    fi
    holder="$(readlink "$lock" 2>/dev/null || true)"
    if [[ -z "$holder" ]]; then
      continue # released between the failed ln and this read; try again
    fi
    if ! kill -0 "$holder" 2>/dev/null; then
      # Only if it still names the dead holder: another waiter may have
      # broken it and taken it since. Two waiters that both read the dead
      # pid can still race here, one removing the lock the other just
      # took; that needs a holder that died in a microseconds-wide window,
      # so it is left open rather than made rename-based.
      [[ "$(readlink "$lock" 2>/dev/null || true)" == "$holder" ]] && rm -f "$lock"
      continue
    fi
    if awk -v e="$elapsed" -v t="$timeout" 'BEGIN{exit !(e >= t)}'; then
      return 1
    fi
    sleep "$interval"
    elapsed="$(awk -v e="$elapsed" -v i="$interval" 'BEGIN{printf "%.2f", e+i}')"
  done
}

# Next strictly-increasing job sequence number, zero-padded so lexical sort
# (what the worker uses to pick the next job) equals numeric/submission
# order.
next_queue_seq() {
  local state_dir="$1" seq_file="$1/queue-seq" seq_lock="$1/queue-seq.lock" seq=0
  if ! acquire_lock "$seq_lock" 5 0.1; then
    echo "error: could not acquire the queue sequence lock" >&2
    return 1
  fi
  [[ -f "$seq_file" ]] && seq="$(<"$seq_file")"
  [[ "$seq" =~ ^[0-9]+$ ]] || seq=0
  seq=$((seq + 1))
  echo "$seq" >"$seq_file"
  rm -rf "$seq_lock"
  printf '%012d' "$seq"
}

# Starts queue-worker.sh in the background if one isn't already running
# (pidfile + liveness check), guarded so concurrent submitters don't race
# to start two.
ensure_queue_worker_running() {
  local state_dir="$1" script_dir="$2"
  local pidfile="$state_dir/queue-worker.pid" starter_lock="$state_dir/queue-worker-starter.lock"
  local existing_pid
  existing_pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    return 0
  fi
  if ! acquire_lock "$starter_lock" 5 0.1; then
    return 0 # another submitter is starting it right now; don't also try
  fi
  existing_pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    rm -rf "$starter_lock"
    return 0
  fi
  # Close every inherited fd above 2 in the forked child before exec-ing
  # the worker. A plain `>file 2>&1` only touches 0/1/2 — a test harness
  # (bats, in particular) holds extra fds open across `run` (a sync pipe, a
  # per-test output-capture file), and a backgrounded child that inherits
  # them keeps the harness blocked waiting for EOF long after the visible
  # test has finished. No-op in normal use, where there's usually nothing
  # above fd 2 to close anyway.
  (
    for fd_dir in /proc/self/fd /dev/fd; do
      [[ -d "$fd_dir" ]] || continue
      for fd_entry in "$fd_dir"/*; do
        fd_num="${fd_entry##*/}"
        [[ "$fd_num" =~ ^[0-9]+$ ]] || continue
        (( fd_num > 2 )) || continue
        eval "exec ${fd_num}>&-" 2>/dev/null || true
      done
      break
    done
    exec nohup "$script_dir/queue-worker.sh" </dev/null >"$state_dir/queue-worker.log" 2>&1
  ) &
  disown
  # Hold the starter lock until the new worker has actually claimed the
  # pidfile — releasing it right after backgrounding would leave a gap a
  # concurrent caller could slip through and start a second worker, since
  # "we ran `&`" and "it wrote its own pidfile" aren't the same instant.
  local new_pid
  for _ in $(seq 1 50); do
    new_pid="$(cat "$pidfile" 2>/dev/null || true)"
    [[ -n "$new_pid" ]] && kill -0 "$new_pid" 2>/dev/null && break
    sleep 0.1
  done
  rm -rf "$starter_lock"
}

# Submits a job and blocks until its result appears: prints the result's
# "output" to stdout and "stderr" to stderr, returns its exit_code.
submit_and_wait() {
  local state_dir="$1" job_json="$2" timeout="$3"
  local queue_dir="$state_dir/queue" results_dir="$state_dir/results"
  mkdir -p "$queue_dir" "$results_dir"

  local seq job_id job_file result_file
  seq="$(next_queue_seq "$state_dir")" || return 1
  job_id="${seq}-$$"
  job_file="$queue_dir/$job_id.job"
  result_file="$results_dir/$job_id.result"
  # Write-then-rename so the worker never observes a partially-written job.
  printf '%s' "$job_json" >"$job_file.tmp"
  mv "$job_file.tmp" "$job_file"

  local waited=0
  while [[ ! -f "$result_file" ]]; do
    if awk -v w="$waited" -v t="$timeout" 'BEGIN{exit !(w >= t)}'; then
      rm -f "$job_file" # best-effort: unclaim it if the worker hasn't taken it yet
      echo "error: timed out after ${timeout}s waiting for the local-LLM queue" >&2
      return 1
    fi
    sleep 0.2
    waited="$(awk -v w="$waited" 'BEGIN{printf "%.1f", w+0.2}')"
  done

  local exit_code output stderr_text
  exit_code="$(jq -r '.exit_code // 1' "$result_file" 2>/dev/null || echo 1)"
  output="$(jq -r '.output // empty' "$result_file" 2>/dev/null || true)"
  stderr_text="$(jq -r '.stderr // empty' "$result_file" 2>/dev/null || true)"
  rm -f "$result_file"

  [[ -n "$stderr_text" ]] && echo "$stderr_text" >&2
  [[ -n "$output" ]] && printf '%s\n' "$output"
  return "$exit_code"
}
