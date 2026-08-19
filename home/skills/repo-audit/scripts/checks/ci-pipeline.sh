#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gh jq git ripgrep
# shellcheck shell=bash
# Usage: ci-pipeline.sh <target> [--fix] [--forge=github|gitlab]
#
# Checks: workflow permissions least-privilege, basic caching present.
# Required-check-vs-job-name matching lives in branch-protection.sh; this
# script only flags workflow-level hygiene. See ../../ci-pipeline.md.
#
# main() is guarded below so scripts/tests/ci-pipeline.test.sh can source
# this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/forge.sh
source "$SCRIPT_DIR/../lib/forge.sh"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

# check_workflow_file <path> — reports permissions + caching findings for one file.
check_workflow_file() {
    local wf="$1"
    local name
    name="$(basename "$wf")"

    if grep -qE '^permissions:\s*write-all\s*$' "$wf"; then
        report_fail "$name: workflow-level 'permissions: write-all' (not least-privilege)"
    elif grep -qE '^\s*permissions:' "$wf"; then
        report_pass "$name: declares explicit permissions"
    else
        report_fail "$name: no explicit permissions block (inherits org/repo default)"
    fi

    if grep -qE 'actions/cache|actions/setup-go.*cache|actions/setup-node.*cache|cachix|niks3|magic-nix-cache' "$wf"; then
        report_pass "$name: has a caching step"
    else
        report_skip "$name: no caching step detected (only a finding if this job builds something cacheable)"
    fi
}

# any_workflow_triggers_on_pull_request <workflows-dir> -> 0/1
any_workflow_triggers_on_pull_request() {
    local dir="$1"
    local wf
    for wf in "$dir"/*.yaml "$dir"/*.yml; do
        [[ -f "$wf" ]] || continue
        # Matches `pull_request:` or `pull_request_target:` as an `on:` key
        # (2-space indented, the convention every workflow here uses).
        grep -qE '^  pull_request(_target)?:' "$wf" && return 0
    done
    return 1
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: ci-pipeline.sh <target> [--fix] [--forge=...]}"
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
    echo "== ci-pipeline ($TARGET_REPO, forge=$FORGE) =="

    if [[ ! -d "$target/.github/workflows" ]]; then
        report_skip "no .github/workflows found (checked out at $target)"
        return 0
    fi

    local wf
    for wf in "$target"/.github/workflows/*.yaml "$target"/.github/workflows/*.yml; do
        [[ -f "$wf" ]] || continue
        check_workflow_file "$wf"
    done

    if any_workflow_triggers_on_pull_request "$target/.github/workflows"; then
        report_pass "at least one workflow triggers on pull_request (required checks can be satisfied)"
    else
        report_fail "no workflow triggers on pull_request — required status checks (branch protection, automerge) can never be satisfied" \
            "add a workflow with 'on: pull_request' so PRs get a check-run at all"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
