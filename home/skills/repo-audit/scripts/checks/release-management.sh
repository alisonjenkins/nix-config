#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gh jq git ripgrep
# shellcheck shell=bash
# Usage: release-management.sh <target> [--fix] [--forge=github|gitlab]
#
# Checks: automated release tooling wired into CI, Conventional Commits
# heuristic, releases actually publishing. See ../../release-management.md.
#
# main() is guarded below so scripts/tests/release-management.test.sh can
# source this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/forge.sh
source "$SCRIPT_DIR/../lib/forge.sh"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

# release_tooling_found <target> -> 0/1
release_tooling_found() {
    local target="$1"
    if [[ -d "$target/.github/workflows" ]] \
        && rg -l -i 'release-please|semantic-release' "$target/.github/workflows" 2>/dev/null | grep -q .; then
        return 0
    fi
    [[ -f "$target/release-please-config.json" ]] && return 0
    [[ -f "$target/.releaserc" || -f "$target/.releaserc.json" || -f "$target/.releaserc.yaml" ]] && return 0
    return 1
}

# conventional_commit_ratio <subjects-text> -> "conventional total"
conventional_commit_ratio() {
    local subjects="$1" total conventional
    total=$(wc -l <<<"$subjects")
    conventional=$(grep -cE '^(feat|fix|chore|docs|refactor|test|build|ci|perf|style)(\(.+\))?!?:' <<<"$subjects" || true)
    echo "$conventional $total"
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: release-management.sh <target> [--fix] [--forge=...]}"
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
    echo "== release-management ($TARGET_REPO, forge=$FORGE) =="

    local tooling_found=false
    if release_tooling_found "$target"; then
        tooling_found=true
        report_pass "automated release tooling found (release-please / semantic-release)"
    else
        report_fail "no automated release tooling found (release-please, semantic-release, etc.)"
    fi

    local subjects=""
    if [[ "$FORGE" == "github" ]]; then
        subjects="$(forge_list_recent_commit_subjects 50)"
    elif [[ -d "$target/.git" ]]; then
        subjects="$(git -C "$target" log -50 --format=%s)"
    fi

    if [[ -n "$subjects" ]]; then
        local ratio conventional total
        ratio="$(conventional_commit_ratio "$subjects")"
        conventional="${ratio% *}"
        total="${ratio#* }"
        if (( total > 0 )) && (( conventional * 100 / total >= 80 )); then
            report_pass "recent commits mostly follow Conventional Commits ($conventional/$total)"
        else
            report_fail "recent commits don't consistently follow Conventional Commits ($conventional/$total)" \
                "release-please/semantic-release need this convention to compute versions"
        fi
    else
        report_skip "no commit history available to check"
    fi

    if [[ "$FORGE" == "github" ]]; then
        local releases
        releases="$(forge_list_releases)"
        if [[ -n "$releases" ]]; then
            report_pass "releases have been published"
        elif [[ "$tooling_found" == "true" ]]; then
            report_fail "release tooling is configured but no release has ever published" \
                "check whether the release PR is being opened but never merged"
        else
            report_skip "no releases and no tooling configured — covered by the tooling-presence finding above"
        fi
    else
        report_skip "release-publish verification requires forge API support (unsupported: $FORGE)"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
