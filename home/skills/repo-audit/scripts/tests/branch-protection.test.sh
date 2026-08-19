#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq
# shellcheck shell=bash
# Unit tests for scripts/checks/branch-protection.sh. `gh` is stubbed (paid
# third-party API — the one thing this suite mocks, per the testing skill's
# mocking policy) with canned JSON; everything else is real.
#
# Usage: ./branch-protection.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/branch-protection.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

# make_github_fixture -> path to a fixture repo with a github origin remote.
make_github_fixture() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@github.com:someowner/somerepo.git
    echo "$repo"
}

# stub_gh <dir> <default-branch-json> <protection-json-or-404>
# The protection endpoint 404s (gh api exits nonzero) when unprotected —
# github_get_branch_protection in lib/github.sh falls back to "{}" for that.
stub_gh() {
    local dir="$1" protection_json="$2"
    stub "$dir" gh "
        case \"\$*\" in
            *branches/main/protection*)
                echo '$protection_json'
                ;;
            *default_branch*)
                echo 'main'
                ;;
            *contents/.github/workflows*)
                echo ''
                ;;
            *)
                echo '{}'
                ;;
        esac
    "
}

test_flags_no_protection_at_all() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub_gh "$d" '{}'
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "no required PR review on main" "main: flags missing required PR review"
    assert_contains "$out" "force-push not disabled on main" "main: flags force-push not disabled"
    assert_contains "$out" "branch deletion not protected on main" "main: flags deletion not protected"
    assert_contains "$out" "no required status checks configured on main" "main: flags no required status checks"
    rm -rf "$repo" "$d"
}

test_passes_when_fully_protected() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub_gh "$d" '{
        "required_pull_request_reviews": {"required_approving_review_count": 1},
        "allow_force_pushes": {"enabled": false},
        "allow_deletions": {"enabled": false},
        "required_status_checks": {"contexts": ["build"]}
    }'
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "required PR reviews configured on main" "main: passes required PR review"
    assert_contains "$out" "force-push disabled on main" "main: passes force-push disabled"
    assert_contains "$out" "branch deletion protected on main" "main: passes deletion protected"
    rm -rf "$repo" "$d"
}

test_flags_stale_required_check() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub_gh "$d" '{
        "required_pull_request_reviews": {"required_approving_review_count": 1},
        "allow_force_pushes": {"enabled": false},
        "allow_deletions": {"enabled": false},
        "required_status_checks": {"contexts": ["renamed-job-nobody-updated"]}
    }'
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "no matching workflow file (stale/renamed job?)" "main: flags a required check with no matching workflow"
    rm -rf "$repo" "$d"
}

test_skips_unsupported_forge() {
    local repo; repo="$(make_fixture_repo)"
    git -C "$repo" remote add origin git@gitlab.com:someowner/somerepo.git
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "unsupported: gitlab" "main: reports unsupported forge cleanly instead of erroring"
    rm -rf "$repo"
}

run_all() {
    test_flags_no_protection_at_all
    test_passes_when_fully_protected
    test_flags_stale_required_check
    test_skips_unsupported_forge
}

run_all
print_summary
