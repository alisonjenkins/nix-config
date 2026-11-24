#!/usr/bin/env bats
# Tests for .github/scripts/update-shepherd.sh. `gh` and `update-policy` are
# stubs on PATH: update-policy prints $STUB_DECISIONS, and gh logs every call
# (with the token it saw) and answers from STUB_* variables.
#
# Run from repo root:
#   nix run nixpkgs#bats -- .github/scripts/tests/update-shepherd.bats

SCRIPT="${BATS_TEST_DIRNAME}/../update-shepherd.sh"

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/bin"
  cat >"$WORK/bin/update-policy" <<EOF
#!$BASH
[ "\$1" = shepherd ] || exit 9
echo "\$*" >>"\$WORK/policy.log"
printf '%s' "\${STUB_DECISIONS:-}"
exit "\${STUB_POLICY_EXIT:-0}"
EOF
  cat >"$WORK/bin/gh" <<EOF
#!$BASH
echo "[\$GH_TOKEN] \$*" >>"\$WORK/gh.log"
case "\$1 \$2" in
  "pr list") [ -z "\${STUB_LIST_FAIL:-}" ] || { echo "HTTP 401" >&2; exit 1; }; echo '[]' ;;
  "pr update-branch") [ -z "\${STUB_REBASE_FAIL:-}" ] || { echo "refusing to allow a GitHub App to update workflow" >&2; exit 1; } ;;
  "issue list") printf '%s' "\${STUB_ISSUE:-}" ;;
  "issue create") echo "https://github.com/o/r/issues/99" ;;
  "issue edit") cp "\$(sed -n 's/.*--body-file \([^ ]*\).*/\1/p' <<<"\$*")" "\$WORK/body.md" ;;
esac
if [ "\$1 \$2" = "issue create" ]; then
  cp "\$(sed -n 's/.*--body-file \([^ ]*\).*/\1/p' <<<"\$*")" "\$WORK/body.md"
fi
EOF
  chmod +x "$WORK/bin/"*
  export PATH="$WORK/bin:$PATH" WORK
  export GH_TOKEN=app ISSUE_TOKEN=issues APP_SLUG=updater GITHUB_REPOSITORY=o/r RUN_URL=https://run/1
  unset GITHUB_STEP_SUMMARY
}

teardown() {
  rm -rf "$WORK"
}

@test "nothing open and no issue: lists PRs with the App token and touches no issue" {
  run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[app] pr list --repo o/r --state open --author app/updater" "$WORK/gh.log"
  grep -qF "[issues] issue list" "$WORK/gh.log"
  ! grep -qE "issue (create|edit|close)" "$WORK/gh.log"
}

@test "the rebase window is passed through only when set" {
  run "$BASH" "$SCRIPT"
  grep -qF -- "--stuck-after-hours 6" "$WORK/policy.log"
  ! grep -qF -- "--rebase-window" "$WORK/policy.log"
  REBASE_WINDOW=00:30-04:30 STUCK_AFTER_HOURS=3 run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF -- "--stuck-after-hours 3 --rebase-window 00:30-04:30" "$WORK/policy.log"
}

@test "behind PR is rebased with the App token" {
  STUB_DECISIONS=$'rebase 1070\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[app] pr update-branch --repo o/r --rebase 1070" "$WORK/gh.log"
  [[ "$output" == *"::notice::#1070 was behind main; rebased it"* ]]
  ! grep -qE "issue (create|edit)" "$WORK/gh.log"
}

@test "a failed rebase is reported as stuck with git's reason" {
  STUB_REBASE_FAIL=1 STUB_DECISIONS=$'rebase 1070\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[issues] issue create --title Nightly flake update is stuck" "$WORK/gh.log"
  grep -qF "#1070 could not be rebased onto main (refusing to allow a GitHub App to update workflow)" "$WORK/body.md"
}

@test "stuck PR opens the issue with every reason and the run link" {
  STUB_DECISIONS=$'stuck 8 superseded by #9\nrebase 9\nstuck 9 check failed: flake-check failure\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::#9 check failed: flake-check failure"* ]]
  grep -qF -- "- #8 superseded by #9" "$WORK/body.md"
  grep -qF -- "- #9 check failed: flake-check failure" "$WORK/body.md"
  grep -qF "by https://run/1" "$WORK/body.md"
  [[ "$output" == *"opened https://github.com/o/r/issues/99"* ]]
}

@test "an open issue is edited in place, not duplicated" {
  STUB_ISSUE=42 STUB_DECISIONS=$'stuck 9 not merged after 6.0h\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[issues] issue edit 42" "$WORK/gh.log"
  ! grep -qF "issue create" "$WORK/gh.log"
}

@test "an open issue is closed once nothing is stuck" {
  STUB_ISSUE=42 STUB_DECISIONS=$'wait 9 open 0.5h\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "[issues] issue close 42 --comment No nightly flake-update PR is stuck any more. Checked by https://run/1. --repo o/r" "$WORK/gh.log"
  [[ "$output" == *"#9: open 0.5h"* ]]
}

@test "the issue search matches the exact title" {
  run "$BASH" "$SCRIPT"
  grep -qF 'select(.title == "Nightly flake update is stuck")' "$WORK/gh.log"
}

@test "decisions go to the step summary" {
  export GITHUB_STEP_SUMMARY="$WORK/summary"
  STUB_DECISIONS=$'wait 9 open 0.5h\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF -- "- wait 9 open 0.5h" "$WORK/summary"
  STUB_DECISIONS="" run "$BASH" "$SCRIPT"
  grep -qF "No open nightly PR." "$WORK/summary"
}

@test "failing to list PRs is an error naming the cause" {
  STUB_LIST_FAIL=1 run "$BASH" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::could not list the updater App's open PRs: HTTP 401"* ]]
}

@test "update-policy failing is an error" {
  STUB_POLICY_EXIT=2 run "$BASH" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::update-policy shepherd failed"* ]]
}

@test "an unknown decision line is an error, not ignored" {
  STUB_DECISIONS=$'merge 9\n' run "$BASH" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not understand: merge 9"* ]]
}

@test "missing environment is named" {
  unset ISSUE_TOKEN
  run "$BASH" "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ISSUE_TOKEN (a token with issues: write) is not set"* ]]
}
