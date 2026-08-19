#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git
# shellcheck shell=bash
# Unit tests for scripts/lib/forge.sh — forge detection, target normalization,
# and the dispatcher's github/gitlab/unknown-forge routing.
#
# Usage: ./forge.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TESTS_DIR/../lib" && pwd)"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=../lib/forge.sh
. "$LIB_DIR/forge.sh"

test_detect_github_ssh_remote() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    forge_detect "$repo"
    assert_eq "github" "$FORGE" "forge_detect: github ssh remote"
    assert_eq "someowner/somerepo" "$TARGET_REPO" "forge_detect: normalizes ssh remote to owner/repo"
    rm -rf "$repo"
}

test_detect_github_https_remote() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin https://github.com/someowner/somerepo.git
    forge_detect "$repo"
    assert_eq "github" "$FORGE" "forge_detect: github https remote"
    assert_eq "someowner/somerepo" "$TARGET_REPO" "forge_detect: normalizes https remote to owner/repo"
    rm -rf "$repo"
}

test_detect_gitlab_remote() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@gitlab.com:someowner/somerepo.git
    forge_detect "$repo"
    assert_eq "gitlab" "$FORGE" "forge_detect: gitlab remote"
    rm -rf "$repo"
}

test_detect_no_remote_is_unknown() {
    local repo; repo="$(make_fixture_repo)"
    forge_detect "$repo"
    assert_eq "unknown" "$FORGE" "forge_detect: no origin remote -> unknown"
    rm -rf "$repo"
}

test_detect_override_wins_over_remote() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    forge_detect "$repo" "--forge=gitlab"
    assert_eq "gitlab" "$FORGE" "forge_detect: --forge= override wins over detected remote"
    rm -rf "$repo"
}

test_detect_bare_owner_repo_shorthand() {
    forge_detect "someowner/somerepo"
    assert_eq "github" "$FORGE" "forge_detect: bare owner/repo (not a checkout) assumes github"
    assert_eq "someowner/somerepo" "$TARGET_REPO" "forge_detect: bare owner/repo passes through as TARGET_REPO"
}

test_dispatch_known_forge_calls_implementation() {
    local d; d="$(make_stub_dir)"
    stub "$d" gh 'echo "main"' # simulates `gh api ... --jq .default_branch` already filtering
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    forge_detect "$repo"
    local out
    out="$(PATH="$d:$PATH" forge_get_default_branch)"
    assert_eq "main" "$out" "forge dispatcher: github_get_default_branch called via forge_get_default_branch"
    rm -rf "$repo" "$d"
}

test_dispatch_gitlab_stub_reports_unsupported() {
    forge_detect "someowner/somerepo" "--forge=gitlab"
    forge_get_branch_protection >/tmp/forge_test_out.$$ 2>&1
    local rc=$?
    assert_exit 2 "$rc" "forge dispatcher: gitlab stub returns 2 (not implemented)"
    assert_contains "$(cat /tmp/forge_test_out.$$)" "unsupported-forge:gitlab" "forge dispatcher: gitlab stub message names the forge+op"
    rm -f /tmp/forge_test_out.$$
}

run_all() {
    test_detect_github_ssh_remote
    test_detect_github_https_remote
    test_detect_gitlab_remote
    test_detect_no_remote_is_unknown
    test_detect_override_wins_over_remote
    test_detect_bare_owner_repo_shorthand
    test_dispatch_known_forge_calls_implementation
    test_dispatch_gitlab_stub_reports_unsupported
}

run_all
print_summary
