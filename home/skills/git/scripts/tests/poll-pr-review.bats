#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../poll-pr-review.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES"
  # defaults: no unresolved threads, no suppressed findings, one verdict line
  : >"$FAKE_GH_FIXTURES/threads.tsv"
  : >"$FAKE_GH_FIXTURES/review-bodies.txt"
  echo "[2026-01-01T00:00:00Z] someone on abcdef12: ### verdict" >"$FAKE_GH_FIXTURES/verdict-line.txt"
}

@test "no args prints usage and exits 1" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "too many args prints usage and exits 1" {
  run "$script" 319 owner/repo extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "non-numeric pr number errors clearly" {
  run "$script" not-a-number owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be numeric"* ]]
}

@test "reports (none) for unresolved threads and suppressed findings when both are empty" {
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unresolved review threads"* ]]
  [[ "$output" == *"Suppressed/previously-missed findings"* ]]
  # two "(none)" lines: one per empty section
  [ "$(grep -c '^(none)$' <<<"$output")" -eq 2 ]
}

@test "lists an unresolved thread with its comment id and path:line" {
  printf 'THREAD_1\tfalse\tsome/file.sh\t42\t1001\talice\tfix this thing\n' \
    >"$FAKE_GH_FIXTURES/threads.tsv"
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1001] some/file.sh:42 (thread THREAD_1)"* ]]
  [[ "$output" == *"alice: fix this thing"* ]]
  [[ "$output" != *"[outdated"* ]]
}

@test "marks an outdated thread" {
  printf 'THREAD_1\ttrue\tsome/file.sh\t42\t1001\talice\tfix this thing\n' \
    >"$FAKE_GH_FIXTURES/threads.tsv"
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[outdated: code has changed since]"* ]]
}

@test "extracts a suppressed finding (file:line header + following bullet)" {
  cat >"$FAKE_GH_FIXTURES/review-bodies.txt" <<'EOF'
### Changes recommended

Some summary text.

**src/foo.sh:12**
* the actual finding text here

- Files reviewed: 1/1
EOF
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/foo.sh:12"* ]]
  [[ "$output" == *"the actual finding text here"* ]]
}

@test "deduplicates the same finding repeated across multiple review bodies" {
  # no separator between bodies: gh --jq concatenates them directly, just
  # like the real `.[] | select(.body != "") | .body` output would
  cat >"$FAKE_GH_FIXTURES/review-bodies.txt" <<'EOF'
**src/foo.sh:12**
* the actual finding text here
**src/foo.sh:12**
* the actual finding text here
EOF
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [ "$(grep -c 'the actual finding text here' <<<"$output")" -eq 1 ]
}

@test "keeps distinct findings at the same location separate" {
  cat >"$FAKE_GH_FIXTURES/review-bodies.txt" <<'EOF'
**src/foo.sh:12**
* first distinct finding
**src/foo.sh:12**
* second distinct finding
EOF
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"first distinct finding"* ]]
  [[ "$output" == *"second distinct finding"* ]]
}

@test "ignores a **file:line** header with no following bullet line" {
  cat >"$FAKE_GH_FIXTURES/review-bodies.txt" <<'EOF'
**src/foo.sh:12**
not a bullet, so this heading has no attached finding

- Files reviewed: 1/1
EOF
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  # still reports (none) for suppressed findings since nothing qualified
  [ "$(grep -c '^(none)$' <<<"$output")" -eq 2 ]
}

@test "shows the precomputed verdict line" {
  run "$script" 319 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[2026-01-01T00:00:00Z] someone on abcdef12: ### verdict"* ]]
}
