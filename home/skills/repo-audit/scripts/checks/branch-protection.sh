#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gh jq git
# shellcheck shell=bash
# Usage: branch-protection.sh <target> [--fix] [--forge=github|gitlab]
#
# Checks: required PR reviews, required status checks (matched against real
# CI job names), force-push disabled, branch deletion protection. See
# ../../branch-protection.md for the full criteria and rationale.
#
# main() is guarded below so scripts/tests/branch-protection.test.sh can
# source this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/forge.sh
source "$SCRIPT_DIR/../lib/forge.sh"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

apply_protection() {
    local branch="$1"
    local payload
    payload=$(jq -n '{
        required_status_checks: null,
        enforce_admins: true,
        required_pull_request_reviews: {required_approving_review_count: 1},
        restrictions: null,
        allow_force_pushes: false,
        allow_deletions: false
    }')
    local tmp
    tmp="$(mktemp)"
    echo "$payload" >"$tmp"
    forge_set_branch_protection "$branch" "$tmp"
    rm -f "$tmp"
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: branch-protection.sh <target> [--fix] [--forge=...]}"
    shift || true
    DO_FIX=false
    local forge_arg=()
    for arg in "$@"; do
        case "$arg" in
            --fix) DO_FIX=true ;;
            --forge=*) forge_arg=("$arg") ;;
        esac
    done
    export DO_FIX

    forge_detect "$target" "${forge_arg[@]:-}"
    echo "== branch-protection ($TARGET_REPO, forge=$FORGE) =="

    if [[ "$FORGE" != "github" ]]; then
        report_skip "branch protection check requires forge API support (unsupported: $FORGE)"
        return 0
    fi

    local branch protection_json
    branch="$(forge_get_default_branch)"
    protection_json="$(forge_get_branch_protection "$branch")"

    if jq -e '.required_pull_request_reviews.required_approving_review_count >= 1' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "required PR reviews configured on $branch"
    else
        report_fail "no required PR review on $branch" "proposed: required_approving_review_count = 1"
        confirm_fix "enable required PR review + force-push/delete protection on $branch" apply_protection "$branch"
    fi

    if jq -e '.allow_force_pushes.enabled == false' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "force-push disabled on $branch"
    else
        report_fail "force-push not disabled on $branch"
    fi

    if jq -e '.allow_deletions.enabled == false' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "branch deletion protected on $branch"
    else
        report_fail "branch deletion not protected on $branch"
    fi

    local required_contexts
    required_contexts="$(jq -r '.required_status_checks.contexts[]? // empty' <<<"$protection_json")"
    if [[ -z "$required_contexts" ]]; then
        report_fail "no required status checks configured on $branch"
    else
        local workflow_job_names
        workflow_job_names="$(forge_list_workflow_files | sed -E 's/\.ya?ml$//')"
        while IFS= read -r ctx; do
            [[ -z "$ctx" ]] && continue
            if grep -qiF "$ctx" <<<"$workflow_job_names"; then
                report_pass "required check '$ctx' matches an existing workflow"
            else
                report_fail "required check '$ctx' has no matching workflow file (stale/renamed job?)"
            fi
        done <<<"$required_contexts"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
