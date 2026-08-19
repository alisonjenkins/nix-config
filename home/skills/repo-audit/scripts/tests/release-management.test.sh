#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq ripgrep
# shellcheck shell=bash
# Unit tests for scripts/checks/release-management.sh. `gh` is stubbed (paid
# third-party API); tooling-presence and commit-convention checks run against
# real fixture files/commits.
#
# Usage: ./release-management.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/release-management.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

make_github_fixture() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    echo "$repo"
}

commit() {
    local repo="$1" msg="$2"
    git -C "$repo" commit -q --allow-empty -m "$msg"
}

test_release_tooling_found_helper() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    echo 'uses: googleapis/release-please-action@v4' > "$repo/.github/workflows/release.yaml"
    release_tooling_found "$repo"
    assert_exit 0 $? "release_tooling_found: detects release-please in a workflow"
    rm -rf "$repo"
}

test_release_tooling_missing_helper() {
    local repo; repo="$(make_fixture_repo)"
    release_tooling_found "$repo"
    assert_exit 1 $? "release_tooling_found: returns 1 when nothing is configured"
    rm -rf "$repo"
}

test_conventional_commit_ratio_helper() {
    local subjects=$'feat: add x\nfix: bug\nwip stuff'
    local ratio
    ratio="$(conventional_commit_ratio "$subjects")"
    assert_eq "2 3" "$ratio" "conventional_commit_ratio: counts conventional vs total"
}

test_main_flags_no_tooling() {
    local repo; repo="$(make_github_fixture)"
    commit "$repo" "feat: initial"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "echo 'feat: initial'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "no automated release tooling found" "main: flags absent release tooling"
    rm -rf "$repo" "$d"
}

test_main_flags_non_conventional_commits() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "printf 'wip\\nasdf\\nmore stuff\\n'"
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "don't consistently follow Conventional Commits" "main: flags non-conventional commit history"
    rm -rf "$repo" "$d"
}

test_main_flags_tooling_configured_but_never_published() {
    local repo; repo="$(make_github_fixture)"
    mkdir -p "$repo/.github/workflows"
    echo 'uses: googleapis/release-please-action@v4' > "$repo/.github/workflows/release.yaml"
    local d; d="$(make_stub_dir)"
    stub "$d" gh "
        case \"\$*\" in
            *releases*) echo '' ;;
            *) echo 'feat: initial' ;;
        esac
    "
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "no release has ever published" "main: flags tooling present but nothing ever published"
    rm -rf "$repo" "$d"
}

run_all() {
    test_release_tooling_found_helper
    test_release_tooling_missing_helper
    test_conventional_commit_ratio_helper
    test_main_flags_no_tooling
    test_main_flags_non_conventional_commits
    test_main_flags_tooling_configured_but_never_published
}

run_all
print_summary
