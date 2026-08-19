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

# stub_gh <dir> <protection-json> [collaborator-count]
# The protection endpoint 404s (gh api exits nonzero) when unprotected —
# github_get_branch_protection in lib/github.sh falls back to "{}" for that.
# collaborator-count defaults to 2 so existing tests exercise the
# multi-collaborator (required-review) path unchanged.
stub_gh() {
    local dir="$1" protection_json="$2" collaborators="${3:-2}"
    stub "$dir" gh "
        case \"\$*\" in
            *branches/main/protection*)
                echo '$protection_json'
                ;;
            *collaborators*)
                echo '$collaborators'
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
    assert_contains "$out" "no matching job (stale/renamed job?)" "main: flags a required check with no matching job"
    rm -rf "$repo" "$d"
}

test_extract_job_ids_helper() {
    local d; d="$(make_stub_dir)"
    printf 'name: x\non:\n  pull_request:\njobs:\n  flake-check:\n    runs-on: ubuntu-latest\n' > "$d/wf.yaml"
    local out
    out="$(extract_job_ids "$d/wf.yaml")"
    assert_eq "flake-check" "$out" "extract_job_ids: reads the job id, not the filename"
    rm -rf "$d"
}

test_matches_required_check_against_job_id_not_filename() {
    # Regression: a workflow file named pr-check.yaml with a job called
    # flake-check must match a required context of "flake-check" — comparing
    # against the filename ("pr-check") would wrongly call this stale.
    local repo; repo="$(make_github_fixture)"
    mkdir -p "$repo/.github/workflows"
    printf 'name: PR check\non:\n  pull_request:\njobs:\n  flake-check:\n    runs-on: ubuntu-latest\n' \
        > "$repo/.github/workflows/pr-check.yaml"
    local d; d="$(make_stub_dir)"
    stub_gh "$d" '{
        "required_pull_request_reviews": {"required_approving_review_count": 1},
        "allow_force_pushes": {"enabled": false},
        "allow_deletions": {"enabled": false},
        "required_status_checks": {"contexts": ["flake-check"]}
    }'
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "required check 'flake-check' matches an existing job" "main: matches a required check against the job id inside a differently-named workflow file"
    rm -rf "$repo" "$d"
}

test_solo_repo_skips_required_review() {
    local repo; repo="$(make_github_fixture)"
    local d; d="$(make_stub_dir)"
    stub_gh "$d" '{
        "allow_force_pushes": {"enabled": false},
        "allow_deletions": {"enabled": false},
        "required_status_checks": {"contexts": ["build"]}
    }' 1
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "solo repo (1 collaborator)" "main: skips (not fails) required review on a solo repo"
    assert_not_contains "$out" "no required PR review on main" "main: does not flag missing review as a failure on a solo repo"
    rm -rf "$repo" "$d"
}

test_apply_protection_reviews_zero_omits_requirement() {
    # apply_protection(branch, required_reviews=0) is what main() calls for a
    # solo repo. Its payload must never set required_approving_review_count,
    # or it locks the only collaborator out (GitHub doesn't count
    # self-approval toward a required review).
    local d; d="$(make_stub_dir)"
    # forge_set_branch_protection passes --input <file>; capture its content
    # by having the stub cat whatever file follows --input.
    stub "$d" gh '
        prev=""
        for a in "$@"; do
            if [[ "$prev" == "--input" ]]; then cat "$a" >&2; fi
            prev="$a"
        done
        exit 0
    '
    FORGE="github"; TARGET_REPO="someowner/somerepo"
    local err
    err="$(PATH="$d:$PATH" apply_protection "main" 0 2>&1 >/dev/null)"
    assert_contains "$err" '"required_pull_request_reviews": null' "apply_protection(reviews=0): payload has no review requirement"
    rm -rf "$d"
}

test_apply_protection_reviews_one_sets_requirement() {
    local d; d="$(make_stub_dir)"
    stub "$d" gh '
        prev=""
        for a in "$@"; do
            if [[ "$prev" == "--input" ]]; then cat "$a" >&2; fi
            prev="$a"
        done
        exit 0
    '
    FORGE="github"; TARGET_REPO="someowner/somerepo"
    local err
    err="$(PATH="$d:$PATH" apply_protection "main" 1 2>&1 >/dev/null)"
    assert_contains "$err" '"required_approving_review_count": 1' "apply_protection(reviews=1): payload sets the review requirement"
    rm -rf "$d"
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
    test_extract_job_ids_helper
    test_matches_required_check_against_job_id_not_filename
    test_solo_repo_skips_required_review
    test_apply_protection_reviews_zero_omits_requirement
    test_apply_protection_reviews_one_sets_requirement
    test_skips_unsupported_forge
}

run_all
print_summary
