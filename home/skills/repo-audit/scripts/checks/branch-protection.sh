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

# extract_job_ids <workflow-file> -> job ids, one per line
# GitHub's required-check "context" for an Actions job is the job id (or its
# `name:`, matrix legs aside), never the workflow filename — a workflow named
# pr-check.yaml can declare a job called `flake-check`, and comparing the
# required context against filenames would call that a stale/renamed check
# even though it's exactly right.
extract_job_ids() {
    local wf="$1"
    sed -n '/^jobs:/,/^[a-zA-Z]/{/^  [a-zA-Z0-9_.-]\+:/p}' "$wf" \
        | sed -E 's/^  ([a-zA-Z0-9_.-]+):.*/\1/'
}

apply_protection() {
    local branch="$1" required_reviews="$2"
    local payload
    payload=$(jq -n --argjson reviews "$required_reviews" '{
        required_status_checks: null,
        enforce_admins: true,
        required_pull_request_reviews: (if $reviews > 0 then {required_approving_review_count: $reviews} else null end),
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

    local branch protection_json collaborators required_reviews needs_fix=false
    branch="$(forge_get_default_branch)"
    protection_json="$(forge_get_branch_protection "$branch")"
    collaborators="$(forge_collaborator_count)"
    required_reviews=1

    if [[ "$collaborators" -le 1 ]]; then
        # Solo repo: GitHub doesn't count self-approval toward required
        # reviews, so required_approving_review_count >= 1 here would lock
        # the only collaborator out of merging anything — including
        # automerge, which can't get a second approval either. Required
        # status checks are the real gate for a solo repo.
        report_skip "solo repo (1 collaborator) — required PR review would lock you out of merging; required status checks are the gate instead"
        required_reviews=0
    elif jq -e '.required_pull_request_reviews.required_approving_review_count >= 1' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "required PR reviews configured on $branch"
    else
        report_fail "no required PR review on $branch" "proposed: required_approving_review_count = 1"
        needs_fix=true
    fi

    if jq -e '.allow_force_pushes.enabled == false' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "force-push disabled on $branch"
    else
        report_fail "force-push not disabled on $branch"
        needs_fix=true
    fi

    if jq -e '.allow_deletions.enabled == false' <<<"$protection_json" >/dev/null 2>&1; then
        report_pass "branch deletion protected on $branch"
    else
        report_fail "branch deletion not protected on $branch"
        needs_fix=true
    fi

    if [[ "$needs_fix" == "true" ]]; then
        confirm_fix "bring branch protection on $branch into line (reviews=$required_reviews, force-push/delete disabled)" \
            apply_protection "$branch" "$required_reviews"
    fi

    local required_contexts
    required_contexts="$(jq -r '.required_status_checks.contexts[]? // empty' <<<"$protection_json")"
    if [[ -z "$required_contexts" ]]; then
        report_fail "no required status checks configured on $branch"
    else
        local known_job_ids
        if [[ -d "$target/.github/workflows" ]]; then
            local wf
            for wf in "$target"/.github/workflows/*.yaml "$target"/.github/workflows/*.yml; do
                [[ -f "$wf" ]] || continue
                known_job_ids+="$(extract_job_ids "$wf")"$'\n'
            done
        else
            # No local checkout: fall back to matching against workflow
            # filenames — weaker (a job id rarely equals its file's name),
            # but the forge API doesn't expose job ids without fetching and
            # parsing each workflow file's content.
            known_job_ids="$(forge_list_workflow_files | sed -E 's/\.ya?ml$//')"
        fi
        while IFS= read -r ctx; do
            [[ -z "$ctx" ]] && continue
            if grep -qiF "$ctx" <<<"$known_job_ids"; then
                report_pass "required check '$ctx' matches an existing job"
            else
                report_fail "required check '$ctx' has no matching job (stale/renamed job?)"
            fi
        done <<<"$required_contexts"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
