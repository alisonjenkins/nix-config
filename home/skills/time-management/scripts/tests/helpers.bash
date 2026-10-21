# Shared bats helpers for the tm tests.

tm_setup() {
  tests_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  scripts_dir="$(cd "$tests_dir/.." && pwd)"
  # shellcheck disable=SC2034 # read by the tests that load this file
  tm="$scripts_dir/tm"
}
