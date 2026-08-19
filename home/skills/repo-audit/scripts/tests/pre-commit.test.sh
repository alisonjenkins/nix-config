#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git ripgrep
# shellcheck shell=bash
# Unit tests for scripts/checks/pre-commit.sh. Local-file check, no forge API.
#
# Usage: ./pre-commit.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/pre-commit.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

test_main_reports_missing_config() {
    local repo; repo="$(make_fixture_repo)"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "no .pre-commit-config.yaml or lefthook.yml found" "main: flags missing config"
    rm -rf "$repo"
}

test_main_flags_uncovered_ecosystem() {
    local repo; repo="$(make_fixture_repo)"
    echo 'repos: []' > "$repo/.pre-commit-config.yaml"
    touch "$repo/Cargo.toml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "Cargo.toml present but no matching hook" "main: flags an ecosystem with no matching hook"
    rm -rf "$repo"
}

test_main_passes_when_hook_matches() {
    local repo; repo="$(make_fixture_repo)"
    echo 'repos: [{hooks: [{id: clippy}]}]' > "$repo/.pre-commit-config.yaml"
    touch "$repo/Cargo.toml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "Cargo.toml ecosystem has a matching hook" "main: passes when a matching hook is present"
    rm -rf "$repo"
}

test_main_flags_not_enforced_in_ci() {
    local repo; repo="$(make_fixture_repo)"
    echo 'repos: []' > "$repo/.pre-commit-config.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "hooks not enforced in CI" "main: flags hooks with no CI enforcement"
    rm -rf "$repo"
}

test_main_passes_when_enforced_via_pre_commit_ci() {
    local repo; repo="$(make_fixture_repo)"
    printf 'repos: []\nci:\n  autofix_commit_msg: x\n' > "$repo/.pre-commit-config.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "hooks enforced in CI" "main: passes when pre-commit.ci ('ci:' key) is configured"
    rm -rf "$repo"
}

test_main_passes_when_enforced_via_github_actions() {
    local repo; repo="$(make_fixture_repo)"
    echo 'repos: []' > "$repo/.pre-commit-config.yaml"
    mkdir -p "$repo/.github/workflows"
    echo 'run: pre-commit run --all-files' > "$repo/.github/workflows/lint.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "hooks enforced in CI" "main: passes when a workflow runs 'pre-commit run --all-files'"
    rm -rf "$repo"
}

run_all() {
    test_main_reports_missing_config
    test_main_flags_uncovered_ecosystem
    test_main_passes_when_hook_matches
    test_main_flags_not_enforced_in_ci
    test_main_passes_when_enforced_via_pre_commit_ci
    test_main_passes_when_enforced_via_github_actions
}

run_all
print_summary
