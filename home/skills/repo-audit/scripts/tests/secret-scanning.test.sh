#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq ripgrep
# shellcheck shell=bash
# Unit tests for scripts/checks/secret-scanning.sh. `gh` is stubbed (paid
# third-party API); the CI-scanner check runs against real fixture files.
#
# Usage: ./secret-scanning.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/secret-scanning.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

make_github_fixture() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    echo "$repo"
}

test_flags_scanning_and_push_protection_disabled() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "echo '{\"secret_scanning\": {\"status\": \"disabled\"}, \"secret_scanning_push_protection\": {\"status\": \"disabled\"}}'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "secret scanning not enabled" "main: flags secret scanning disabled"
    assert_contains "$out" "push protection not enabled" "main: flags push protection disabled"
    rm -rf "$repo" "$d"
}

test_passes_when_both_enabled() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "echo '{\"secret_scanning\": {\"status\": \"enabled\"}, \"secret_scanning_push_protection\": {\"status\": \"enabled\"}}'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "secret scanning enabled" "main: passes when secret scanning enabled"
    assert_contains "$out" "push protection enabled" "main: passes when push protection enabled"
    rm -rf "$repo" "$d"
}

test_scanner_required_not_optional() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "echo '{\"secret_scanning\": {\"status\": \"enabled\"}, \"secret_scanning_push_protection\": {\"status\": \"enabled\"}}'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "required, not optional" "main: CI scanner absence is a hard fail, not a skip"
    rm -rf "$repo" "$d"
}

test_passes_when_gitleaks_step_present_locally() {
    local repo; repo="$(make_github_fixture)"
    mkdir -p "$repo/.github/workflows"
    echo 'uses: gitleaks/gitleaks-action@v2' > "$repo/.github/workflows/scan.yaml"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "echo '{\"secret_scanning\": {\"status\": \"enabled\"}, \"secret_scanning_push_protection\": {\"status\": \"enabled\"}}'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "CI-level secret scanner (gitleaks/trufflehog) found in pipeline" "main: finds a local gitleaks workflow step"
    rm -rf "$repo" "$d"
}

run_all() {
    test_flags_scanning_and_push_protection_disabled
    test_passes_when_both_enabled
    test_scanner_required_not_optional
    test_passes_when_gitleaks_step_present_locally
}

run_all
print_summary
