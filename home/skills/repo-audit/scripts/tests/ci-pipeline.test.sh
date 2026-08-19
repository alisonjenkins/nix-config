#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git
# shellcheck shell=bash
# Unit tests for scripts/checks/ci-pipeline.sh. Reads workflow files directly
# — no forge API calls, no stubs needed.
#
# Usage: ./ci-pipeline.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/ci-pipeline.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

test_main_skips_repo_without_workflows() {
    local repo; repo="$(make_fixture_repo)"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "no .github/workflows found" "main: skips a repo with no workflows dir"
    rm -rf "$repo"
}

test_flags_write_all_permissions() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    printf 'name: x\npermissions: write-all\njobs: {}\n' > "$repo/.github/workflows/x.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "x.yaml: workflow-level 'permissions: write-all'" "main: flags write-all permissions"
    rm -rf "$repo"
}

test_passes_explicit_permissions() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    printf 'name: x\npermissions:\n  contents: read\njobs: {}\n' > "$repo/.github/workflows/x.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "x.yaml: declares explicit permissions" "main: passes explicit least-privilege permissions"
    rm -rf "$repo"
}

test_flags_missing_permissions_block() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    printf 'name: x\njobs: {}\n' > "$repo/.github/workflows/x.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "x.yaml: no explicit permissions block" "main: flags absent permissions block"
    rm -rf "$repo"
}

test_passes_caching_step() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    printf 'name: x\npermissions:\n  contents: read\njobs:\n  b:\n    steps:\n      - uses: actions/cache@v4\n' > "$repo/.github/workflows/x.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "x.yaml: has a caching step" "main: recognizes actions/cache as a caching step"
    rm -rf "$repo"
}

run_all() {
    test_main_skips_repo_without_workflows
    test_flags_write_all_permissions
    test_passes_explicit_permissions
    test_flags_missing_permissions_block
    test_passes_caching_step
}

run_all
print_summary
