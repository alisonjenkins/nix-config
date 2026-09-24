#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../watch-pr.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES"

  # Fast loop by default: near-zero sleep, quick idle timeout, so tests
  # don't wait on real wall-clock time.
  export WATCH_PR_START_INTERVAL=0
  export WATCH_PR_MAX_INTERVAL=0
  export WATCH_PR_MAX_SECONDS=0

  origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  repo="$BATS_TEST_TMPDIR/repo"
  git clone -q "$origin" "$repo"
  cd "$repo"
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false

  echo base >base.txt
  git add base.txt
  git commit -q -m base
  git branch -M main
  git push -q -u origin main
  git remote set-head origin main

  git switch -q -c feature
  echo feature >feature.txt
  git add feature.txt
  git commit -q -m feature
  git push -q -u origin feature
}

@test "no args prints usage and exits 1" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "non-numeric pr number errors clearly" {
  run "$script" not-a-number
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be numeric"* ]]
}

@test "rejects owner/repo with no slash" {
  run "$script" 1 ownerrepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be exactly 'owner/repo'"* ]]
}

@test "idle timeout fires when nothing changes and max_seconds is 0" {
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
  [[ "$output" != *"NEW_ACTIVITY"* ]]
  [[ "$output" != *"NEEDS_ATTENTION"* ]]
}

@test "detects new activity when the PR fingerprint changes between ticks" {
  WATCH_PR_MAX_SECONDS=999999
  export WATCH_PR_MAX_SECONDS
  printf 'OPEN\tnull\t2026-01-01T00:00:00Z\tMERGEABLE\tCLEAN\t0\nOPEN\tCHANGES_REQUESTED\t2026-01-01T00:05:00Z\tMERGEABLE\tCLEAN\t1\n' \
    >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_ACTIVITY"* ]]
  [[ "$output" == *"CHANGES_REQUESTED"* ]]
}

@test "a rebase conflict surfaces as NEEDS_ATTENTION and stops the loop" {
  # Diverge origin/main and the local feature branch on the same line so
  # rebasing feature onto main hits a real conflict.
  git switch -q main
  echo "main-side change" >feature.txt
  git add feature.txt
  git commit -q -m "main diverges"
  git push -q origin main
  git switch -q feature

  run "$script" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"NEEDS_ATTENTION"* ]]
  [[ "$output" == *"conflict"* ]]
}

@test "a clean upstream rebase happens silently and is not mistaken for activity" {
  # origin/main advances with a non-conflicting commit; the loop should
  # rebase+push feature onto it on tick 1, then see no *further* change
  # on tick 2 and idle out -- not report NEW_ACTIVITY for its own push.
  git switch -q main
  echo "unrelated" >unrelated.txt
  git add unrelated.txt
  git commit -q -m "main moves on"
  git push -q origin main
  git switch -q feature

  WATCH_PR_MAX_SECONDS=1
  export WATCH_PR_MAX_SECONDS
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
  [[ "$output" != *"NEW_ACTIVITY"* ]]

  # feature must actually have been rebased and pushed onto the new main.
  run git -C "$repo" merge-base --is-ancestor origin/main feature
  [ "$status" -eq 0 ]
}

@test "a gh failure while fetching the fingerprint reports NEEDS_ATTENTION" {
  touch "$FAKE_GH_FIXTURES/fingerprint-fails"
  run "$script" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEEDS_ATTENTION"* ]]
}

@test "a non-numeric WATCH_PR_RATIO falls back to 1.5 instead of collapsing the interval" {
  WATCH_PR_RATIO=not-a-number
  export WATCH_PR_RATIO
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not a number >= 1"* ]]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
}

@test "a WATCH_PR_RATIO below 1 falls back to 1.5 instead of shrinking the interval" {
  WATCH_PR_RATIO=0.5
  export WATCH_PR_RATIO
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not a number >= 1"* ]]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
}

@test "WATCH_PR_START_INTERVAL=0 is accepted, not rejected as non-positive" {
  WATCH_PR_START_INTERVAL=0
  export WATCH_PR_START_INTERVAL
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning:"* ]]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
}

@test "the interval ramps up even when truncation would otherwise stall it" {
  WATCH_PR_START_INTERVAL=1
  WATCH_PR_RATIO=1.5
  WATCH_PR_MAX_SECONDS=999999
  WATCH_PR_MAX_INTERVAL=900
  export WATCH_PR_START_INTERVAL WATCH_PR_RATIO WATCH_PR_MAX_SECONDS WATCH_PR_MAX_INTERVAL
  # 3 distinct fingerprints so the loop runs 3 ticks (sleeping 1, then a
  # rounded-up 2s) before the 4th tick reports the last one as new
  # activity -- if 1*1.5 truncated to 1 instead of rounding up, this
  # would still eventually finish, so the real assertion is on the sleep
  # calls a spy captures below, not on wall-clock time.
  printf 'OPEN\tnull\tA\tMERGEABLE\tCLEAN\t0\nOPEN\tnull\tA\tMERGEABLE\tCLEAN\t0\nOPEN\tnull\tB\tMERGEABLE\tCLEAN\t0\n' \
    >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"

  sleep_log="$BATS_TEST_TMPDIR/sleep-log.txt"
  cat >"$BATS_TEST_TMPDIR/sleep" <<SPY
#!/usr/bin/env bash
echo "\$1" >>"$sleep_log"
SPY
  chmod +x "$BATS_TEST_TMPDIR/sleep"
  PATH="$BATS_TEST_TMPDIR:$PATH" run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_ACTIVITY"* ]]
  # First sleep at the start interval (1), second must be 2 (ceil(1.5)),
  # not 1 again -- proves the ramp actually advances.
  run cat "$sleep_log"
  [[ "$output" == $'1\n2' ]]
}

@test "exits immediately when the PR is already MERGED at startup" {
  printf 'MERGED\tnull\tA\tMERGEABLE\tUNKNOWN\t0\n' >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR_MERGED"* ]]
  [[ "$output" != *"IDLE_TIMEOUT"* ]]
}

@test "exits immediately when the PR is already CLOSED at startup" {
  printf 'CLOSED\tnull\tA\tMERGEABLE\tUNKNOWN\t0\n' >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR_CLOSED"* ]]
  [[ "$output" != *"IDLE_TIMEOUT"* ]]
}

@test "idle timeout is reported in a readable duration, not truncated hours" {
  WATCH_PR_MAX_SECONDS=90
  export WATCH_PR_MAX_SECONDS
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDLE_TIMEOUT: no activity in 0h01m30s"* ]]
  [[ "$output" == *"idle timeout 0h01m30s"* ]]
}

@test "stray stderr from gh doesn't get folded into the fingerprint" {
  WATCH_PR_MAX_SECONDS=1
  export WATCH_PR_MAX_SECONDS
  touch "$FAKE_GH_FIXTURES/fingerprint-stderr-noise"
  run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
  [[ "$output" != *"NEW_ACTIVITY"* ]]
}

@test "a review that landed after triage is reported on tick 1 instead of becoming the baseline" {
  printf 'OPEN\tnull\t2026-01-01T00:00:00Z\tMERGEABLE\tCLEAN\t1\n' \
    >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"
  WATCH_PR_TRIAGED_REVIEWS=0 run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEW_ACTIVITY"* ]]
  [[ "$output" == *"triaged 0 review(s)"* ]]
}

@test "a matching WATCH_PR_TRIAGED_REVIEWS keeps the normal baseline behaviour" {
  printf 'OPEN\tnull\t2026-01-01T00:00:00Z\tMERGEABLE\tCLEAN\t1\n' \
    >"$FAKE_GH_FIXTURES/fingerprint-sequence.tsv"
  WATCH_PR_TRIAGED_REVIEWS=1 run "$script" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"IDLE_TIMEOUT"* ]]
}
