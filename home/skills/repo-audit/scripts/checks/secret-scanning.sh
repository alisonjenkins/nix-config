#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gh jq git ripgrep
# shellcheck shell=bash
# Usage: secret-scanning.sh <target> [--fix] [--forge=github|gitlab]
#
# Checks: forge-native secret scanning + push protection, and a required
# CI-level scanner job (gitleaks/trufflehog). All three are hard requirements
# — see ../../secret-scanning.md.
#
# main() is guarded below so scripts/tests/secret-scanning.test.sh can source
# this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/forge.sh
source "$SCRIPT_DIR/../lib/forge.sh"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

apply_enable_scanning() {
    forge_enable_secret_scanning true
}

# ci_scanner_found <target> <forge>
ci_scanner_found() {
    local target="$1" forge="$2"
    local local_path="$target"
    if [[ ! -d "$local_path/.git" ]]; then
        local_path="" # not a local checkout; can't inspect workflow files directly
    fi

    if [[ -n "$local_path" ]]; then
        # Only search paths that actually exist: rg exits nonzero for a
        # missing path even when it matched in a sibling path, and that
        # nonzero rightmost-of-pipeline status trips `set -o pipefail` in
        # main() and is mistaken for "no scanner found".
        local search_paths=()
        [[ -d "$local_path/.github/workflows" ]] && search_paths+=("$local_path/.github/workflows")
        [[ -f "$local_path/.gitlab-ci.yml" ]] && search_paths+=("$local_path/.gitlab-ci.yml")
        if [[ ${#search_paths[@]} -gt 0 ]] \
            && rg -l -i 'gitleaks|trufflehog' "${search_paths[@]}" 2>/dev/null | grep -q .; then
            return 0
        fi
        return 1
    fi

    if [[ "$forge" == "github" ]]; then
        local workflow_names
        workflow_names="$(forge_list_workflow_files)"
        while IFS= read -r wf; do
            [[ -z "$wf" ]] && continue
            if gh api "repos/$TARGET_REPO/contents/.github/workflows/$wf" --jq '.content' 2>/dev/null \
                | base64 -d 2>/dev/null | grep -qiE 'gitleaks|trufflehog'; then
                return 0
            fi
        done <<<"$workflow_names"
    fi
    return 1
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: secret-scanning.sh <target> [--fix] [--forge=...]}"
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
    echo "== secret-scanning ($TARGET_REPO, forge=$FORGE) =="

    if [[ "$FORGE" == "github" ]]; then
        local status_json
        status_json="$(forge_get_secret_scanning_status)"
        if jq -e '.secret_scanning.status == "enabled"' <<<"$status_json" >/dev/null 2>&1; then
            report_pass "secret scanning enabled"
        else
            report_fail "secret scanning not enabled"
            confirm_fix "enable secret scanning + push protection" apply_enable_scanning
        fi

        if jq -e '.secret_scanning_push_protection.status == "enabled"' <<<"$status_json" >/dev/null 2>&1; then
            report_pass "push protection enabled"
        else
            report_fail "push protection not enabled"
        fi
    else
        report_skip "forge-native secret scanning requires forge API support (unsupported: $FORGE)"
    fi

    if ci_scanner_found "$target" "$FORGE"; then
        report_pass "CI-level secret scanner (gitleaks/trufflehog) found in pipeline"
    else
        report_fail "no CI-level secret scanner job found — required, not optional" \
            "add a gitleaks or trufflehog step to CI and mark it a required status check"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
