# Sourced by the niks3-backfill wrapper and by bats unit tests.
# Required env: CACHE_URL, SERVER_URL, AUTH_TOKEN_FILE
# Optional env: NIKS3_BACKFILL_CHECK_PROCS    (default 64)
#               NIKS3_BACKFILL_PROCS          (default 1)
#               NIKS3_BACKFILL_JOBS           (default 4)
#               NIKS3_BACKFILL_BATCH          (default 500)
#               NIKS3_BACKFILL_DRAIN_INTERVAL (default 5; seconds, fractional ok)

hash_for_path() {
  basename "$1" | cut -c1-32
}

check_path() {
  local p="$1"
  local hash
  hash="$(hash_for_path "$p")"
  if ! curl -sf -o /dev/null --max-time 10 -I "${CACHE_URL%/}/${hash}.narinfo"; then
    printf '%s\n' "$p"
  fi
}

# Two stages, decoupled by an in-kernel FIFO (named pipe):
#   * Checker — parallel CDN HEAD via xargs -P; each miss is a single
#               line-sized write to the FIFO. Writes ≤PIPE_BUF (4096 B) on a
#               FIFO are atomic per POSIX, so concurrent -P workers can't
#               tear lines.
#   * Pusher  — reads from the FIFO with a per-line timeout. Flushes the
#               accumulated batch when either (a) the batch reaches
#               $NIKS3_BACKFILL_BATCH lines or (b) the read times out
#               (i.e. the checker has gone idle). After the checker signals
#               EOF via $done_marker, the pusher does a final non-blocking
#               drain and exits.
#
# Zero on-disk queue, zero inodes per miss. The FIFO inode itself sits in
# tmpfs ($TMPDIR), kernel-buffered. Memory bound is one FIFO buffer (~64 KB
# Linux, ~16 KB macOS) plus the pusher's bash array of ≤BATCH lines.
run_backfill() (
  set -uo pipefail
  # Disable any inherited ERR/DEBUG/RETURN traps and errexit/errtrace —
  # bats installs an ERR trap (via `set -E`) that turns every read-timeout
  # or kill-of-already-dead child into a "failure" inside this subshell.
  # We handle errors explicitly via $? checks and pipefail.
  set +eE
  trap - ERR DEBUG RETURN

  : "${NIKS3_BACKFILL_CHECK_PROCS:=64}"
  : "${NIKS3_BACKFILL_PROCS:=1}"
  : "${NIKS3_BACKFILL_JOBS:=4}"
  : "${NIKS3_BACKFILL_BATCH:=500}"
  : "${NIKS3_BACKFILL_DRAIN_INTERVAL:=5}"

  # Pass the token to niks3 via NIKS3_AUTH_TOKEN_FILE rather than --auth-token
  # so the token never enters the niks3 process's argv (where it would be
  # visible to any local user via `ps`). niks3 reads the file itself.
  export NIKS3_AUTH_TOKEN_FILE="$AUTH_TOKEN_FILE"
  export CACHE_URL
  export -f hash_for_path check_path

  local workdir
  workdir="$(mktemp -d)"
  local input="$workdir/input"
  local fifo="$workdir/queue"
  local done_marker="$workdir/checker.done"
  mkfifo "$fifo"

  local checker_pid=""
  # shellcheck disable=SC2329  # invoked via `trap`
  cleanup() {
    local ec=$?
    if [ -n "$checker_pid" ]; then
      kill "$checker_pid" 2>/dev/null || true
      wait "$checker_pid" 2>/dev/null || true
    fi
    exec 8<&- 2>/dev/null || true
    rm -rf "$workdir"
    exit "$ec"
  }
  trap cleanup EXIT INT TERM

  echo "Enumerating local store paths..." >&2
  nix path-info --all | grep -v '\.drv$' > "$input"
  local total
  total="$(wc -l < "$input")"
  echo "Checking $total paths against $CACHE_URL with $NIKS3_BACKFILL_CHECK_PROCS workers..." >&2

  # Open FIFO RDWR on the reader side: open() returns immediately (no need
  # to wait for a writer) and `read` will not see EOF when the checker
  # closes its writer — we use $done_marker for end-of-stream instead.
  # fd 8 (not 3) — bats reserves fd 3 for its test-runner protocol.
  exec 8<>"$fifo"

  # Checker subshell: opens fd 9 to the FIFO once, xargs -P workers inherit
  # it and write misses concurrently. PIPE_BUF guarantees atomic line writes.
  (
    exec 9>"$fifo"
    # shellcheck disable=SC2016  # $1 expands inside inner bash
    < "$input" xargs -r -n1 -P "$NIKS3_BACKFILL_CHECK_PROCS" \
      bash -c '
        out="$(check_path "$1")"
        [ -n "$out" ] && printf "%s\n" "$out" >&9
      ' _
    exec 9>&-
    touch "$done_marker"
  ) &
  checker_pid=$!

  local pusher_ec=0
  local pushed=0
  local -a batch=()

  flush() {
    local n=${#batch[@]}
    (( n == 0 )) && return 0
    pushed=$((pushed + n))
    echo "[pusher] pushing $n paths (cumulative: $pushed)" >&2
    if ! printf '%s\n' "${batch[@]}" \
         | xargs -r -n "$NIKS3_BACKFILL_BATCH" -P "$NIKS3_BACKFILL_PROCS" \
             niks3 push \
               --server-url "$SERVER_URL" \
               --max-concurrent-uploads "$NIKS3_BACKFILL_JOBS"; then
      pusher_ec=1
    fi
    batch=()
  }

  local line=""
  while :; do
    if IFS= read -t "$NIKS3_BACKFILL_DRAIN_INTERVAL" -r line <&8; then
      [ -n "$line" ] && batch+=("$line")
      if (( ${#batch[@]} >= NIKS3_BACKFILL_BATCH )); then
        flush
      fi
      continue
    fi
    # Idle: opportunistic flush.
    flush
    if [ -e "$done_marker" ]; then
      # Checker done — final non-blocking drain in case writes landed
      # between our last read and seeing the marker.
      while IFS= read -t 0.1 -r line <&8; do
        [ -n "$line" ] && batch+=("$line")
        if (( ${#batch[@]} >= NIKS3_BACKFILL_BATCH )); then
          flush
        fi
      done
      flush
      break
    fi
  done

  wait "$checker_pid" || pusher_ec=1
  checker_pid=""
  echo "Backfill complete. Enumerated $total, pushed $pushed." >&2
  return "$pusher_ec"
)
