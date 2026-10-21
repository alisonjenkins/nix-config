# Shared bats helpers for the pm tests.

pm_setup() {
  tests_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  scripts_dir="$(cd "$tests_dir/.." && pwd)"
  pm="$scripts_dir/pm"
}

# Puts a fake gh first on PATH. fake-gh.sh holds its body; a shebang that
# resolves in this environment is prepended here. Fixtures live in
# $FAKE_GH_FIXTURES; every call is appended to calls.log.
install_fake_gh() {
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES" "$BATS_TEST_TMPDIR/bin"
  { printf '#!%s\n' "$(command -v bash)"; cat "$tests_dir/fake-gh.sh"; } >"$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  : >"$FAKE_GH_FIXTURES/calls.log"
  echo '[]' >"$FAKE_GH_FIXTURES/list.json"
  echo '[]' >"$FAKE_GH_FIXTURES/epics.json"
  echo '{}' >"$FAKE_GH_FIXTURES/view.json"
}

# True if gh was asked to change anything.
gh_mutated() {
  grep -qE '^(issue (create|edit|close|reopen|comment)|label create)' "$FAKE_GH_FIXTURES/calls.log"
}

# Fails the test if gh was asked to change anything. Written with `if` because
# bats does not fail a test on a negated command (`! cmd`).
refute_mutated() {
  if gh_mutated; then
    echo "gh was asked to change something:"
    cat "$FAKE_GH_FIXTURES/calls.log"
    return 1
  fi
}

# refute_logged <pattern>: fails the test if a gh call matching the pattern was logged.
refute_logged() {
  if grep -q -- "$1" "$FAKE_GH_FIXTURES/calls.log"; then
    echo "unexpected gh call matching: $1"
    return 1
  fi
}
