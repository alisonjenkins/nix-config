#!/usr/bin/env bats
# Unit tests for backfill.sh — exercises hash extraction, CDN-presence check,
# and the end-to-end run_backfill pipeline with stubbed nix/curl/niks3.

setup() {
  TESTDIR="$(mktemp -d)"
  STUBS="$TESTDIR/stubs"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
  export PATH

  # Stubs are bash scripts; record the absolute path so heredoc-generated
  # stubs work in the Nix sandbox where /usr/bin/env is absent.
  BASH_BIN="$(command -v bash)"
  export BASH_BIN

  # shellcheck source=../backfill.sh
  source "${BATS_TEST_DIRNAME}/../backfill.sh"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "hash_for_path: extracts 32-char base32 hash from store path" {
  result="$(hash_for_path /nix/store/abcdefghijklmnopqrstuvwxyz012345-foo-1.0)"
  [ "$result" = "abcdefghijklmnopqrstuvwxyz012345" ]
}

@test "hash_for_path: ignores name suffix containing dashes" {
  result="$(hash_for_path /nix/store/abc12def3ghi4jkl5mno6pqr7stu8vw9-foo-bar-baz)"
  [ "$result" = "abc12def3ghi4jkl5mno6pqr7stu8vw9" ]
}

@test "check_path: emits path when curl returns non-zero (cache miss)" {
  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 22
EOF
  chmod +x "$STUBS/curl"

  CACHE_URL="https://cache.example/"
  export CACHE_URL

  run check_path /nix/store/abc12def3ghi4jkl5mno6pqr7stu8vw9-foo
  [ "$status" -eq 0 ]
  [ "$output" = "/nix/store/abc12def3ghi4jkl5mno6pqr7stu8vw9-foo" ]
}

@test "check_path: emits nothing when curl returns zero (cache hit)" {
  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 0
EOF
  chmod +x "$STUBS/curl"

  CACHE_URL="https://cache.example/"
  export CACHE_URL

  run check_path /nix/store/abc12def3ghi4jkl5mno6pqr7stu8vw9-foo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_path: queries narinfo at <cacheUrl>/<hash>.narinfo" {
  CURL_LOG="$TESTDIR/curl.log"
  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
echo "\$@" >> "$CURL_LOG"
exit 0
EOF
  chmod +x "$STUBS/curl"

  CACHE_URL="https://cache.example"
  export CACHE_URL

  check_path /nix/store/abcdefghijklmnopqrstuvwxyz012345-foo
  grep -q "https://cache.example/abcdefghijklmnopqrstuvwxyz012345.narinfo" "$CURL_LOG"
}

@test "run_backfill: pushes only paths missing from CDN" {
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-cached-1
  echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-missing-1
  echo /nix/store/cccccccccccccccccccccccccccccccc-cached-2
fi
EOF
  chmod +x "$STUBS/nix"

  # 200 (exit 0) for a*/c* hashes, non-zero for the b* hash.
  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
url="\${@: -1}"
case "\$url" in
  *bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb*) exit 22 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUBS/curl"

  NIKS3_LOG="$TESTDIR/niks3.log"
  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
echo "\$@" >> "$NIKS3_LOG"
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "tok" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  NIKS3_BACKFILL_CHECK_PROCS=1
  NIKS3_BACKFILL_PROCS=1
  NIKS3_BACKFILL_JOBS=1
  NIKS3_BACKFILL_BATCH=10
  NIKS3_BACKFILL_DRAIN_INTERVAL=0.2
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_LOG \
    NIKS3_BACKFILL_CHECK_PROCS NIKS3_BACKFILL_PROCS \
    NIKS3_BACKFILL_JOBS NIKS3_BACKFILL_BATCH NIKS3_BACKFILL_DRAIN_INTERVAL

  run_backfill

  [ -f "$NIKS3_LOG" ]
  grep -q -- "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-missing-1" "$NIKS3_LOG"
  ! grep -q -- "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-cached-1" "$NIKS3_LOG"
  ! grep -q -- "/nix/store/cccccccccccccccccccccccccccccccc-cached-2" "$NIKS3_LOG"
}

@test "run_backfill: never passes auth token via niks3 argv" {
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-missing
fi
EOF
  chmod +x "$STUBS/nix"

  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 22
EOF
  chmod +x "$STUBS/curl"

  NIKS3_LOG="$TESTDIR/niks3.log"
  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
echo "argv: \$@" >> "$NIKS3_LOG"
echo "env-NIKS3_AUTH_TOKEN_FILE: \${NIKS3_AUTH_TOKEN_FILE:-unset}" >> "$NIKS3_LOG"
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "supersecrettoken" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  NIKS3_BACKFILL_CHECK_PROCS=1
  NIKS3_BACKFILL_DRAIN_INTERVAL=0.2
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_LOG \
    NIKS3_BACKFILL_CHECK_PROCS NIKS3_BACKFILL_DRAIN_INTERVAL

  run_backfill

  ! grep -q "supersecrettoken" "$NIKS3_LOG"
  ! grep -q -- "--auth-token" "$NIKS3_LOG"
  grep -q "env-NIKS3_AUTH_TOKEN_FILE: $AUTH_TOKEN_FILE" "$NIKS3_LOG"
}

@test "run_backfill: FIFO queue flushes once per BATCH plus a final timeout flush" {
  # 3 misses, BATCH=2 → expect exactly 2 niks3 invocations: one when the
  # batch fills (paths 1+2), one on the idle timeout (path 3).
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-miss-1
  echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-miss-2
  echo /nix/store/cccccccccccccccccccccccccccccccc-miss-3
fi
EOF
  chmod +x "$STUBS/nix"

  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 22
EOF
  chmod +x "$STUBS/curl"

  NIKS3_LOG="$TESTDIR/niks3.log"
  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
# Each invocation appends one marker line plus its argv.
{ echo "INVOCATION"; printf '%s\n' "\$@"; } >> "$NIKS3_LOG"
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "tok" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  # Serialize the checker so misses arrive in order; otherwise -P shuffling
  # makes the per-batch arrival timing non-deterministic.
  NIKS3_BACKFILL_CHECK_PROCS=1
  NIKS3_BACKFILL_BATCH=2
  NIKS3_BACKFILL_DRAIN_INTERVAL=0.2
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_LOG \
    NIKS3_BACKFILL_CHECK_PROCS NIKS3_BACKFILL_BATCH NIKS3_BACKFILL_DRAIN_INTERVAL

  run_backfill

  invocations="$(grep -c "^INVOCATION$" "$NIKS3_LOG")"
  echo "invocations=$invocations" >&2
  cat "$NIKS3_LOG" >&2
  [ "$invocations" -eq 2 ]
  grep -q "miss-1" "$NIKS3_LOG"
  grep -q "miss-2" "$NIKS3_LOG"
  grep -q "miss-3" "$NIKS3_LOG"
}

@test "run_backfill: skips niks3 push entirely when all paths cached" {
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-cached-1
  echo /nix/store/cccccccccccccccccccccccccccccccc-cached-2
fi
EOF
  chmod +x "$STUBS/nix"

  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 0
EOF
  chmod +x "$STUBS/curl"

  NIKS3_LOG="$TESTDIR/niks3.log"
  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
echo "\$@" >> "$NIKS3_LOG"
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "tok" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  NIKS3_BACKFILL_CHECK_PROCS=1
  NIKS3_BACKFILL_DRAIN_INTERVAL=0.2
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_LOG \
    NIKS3_BACKFILL_CHECK_PROCS NIKS3_BACKFILL_DRAIN_INTERVAL

  run_backfill

  [ ! -f "$NIKS3_LOG" ] || [ ! -s "$NIKS3_LOG" ]
}

@test "run_backfill: filters out .drv paths before checking" {
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-foo.drv
  echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-bar
fi
EOF
  chmod +x "$STUBS/nix"

  CURL_LOG="$TESTDIR/curl.log"
  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
echo "\$@" >> "$CURL_LOG"
exit 0
EOF
  chmod +x "$STUBS/curl"

  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
exit 0
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "tok" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  NIKS3_BACKFILL_CHECK_PROCS=1
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_BACKFILL_CHECK_PROCS

  run_backfill

  ! grep -q "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$CURL_LOG"
  grep -q "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$CURL_LOG"
}

@test "run_backfill: propagates niks3 push failure via pipefail" {
  cat > "$STUBS/nix" <<EOF
#!$BASH_BIN
if [ "\$1" = "path-info" ] && [ "\$2" = "--all" ]; then
  echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-missing
fi
EOF
  chmod +x "$STUBS/nix"

  cat > "$STUBS/curl" <<EOF
#!$BASH_BIN
exit 22
EOF
  chmod +x "$STUBS/curl"

  cat > "$STUBS/niks3" <<EOF
#!$BASH_BIN
exit 1
EOF
  chmod +x "$STUBS/niks3"

  AUTH_TOKEN_FILE="$TESTDIR/token"
  echo "tok" > "$AUTH_TOKEN_FILE"
  CACHE_URL="https://cache.example"
  SERVER_URL="https://api.example"
  NIKS3_BACKFILL_CHECK_PROCS=1
  export AUTH_TOKEN_FILE CACHE_URL SERVER_URL NIKS3_BACKFILL_CHECK_PROCS

  run run_backfill
  [ "$status" -ne 0 ]
}
