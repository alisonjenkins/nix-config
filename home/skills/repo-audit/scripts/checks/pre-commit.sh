#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git ripgrep
# shellcheck shell=bash
# Usage: pre-commit.sh <target> [--fix]
#
# Local-repo-only, no forge API — runs the same regardless of forge. See
# ../../pre-commit.md.
#
# main() is guarded below so scripts/tests/pre-commit.test.sh can source
# this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

declare -A ECOSYSTEM_HOOK_HINTS=(
    [Cargo.toml]="cargo|rustfmt|clippy"
    [package.json]="eslint|prettier|npm"
    [go.mod]="golangci|gofmt|go vet"
    [flake.nix]="nixpkgs-fmt|alejandra|statix|deadnix"
    [pyproject.toml]="black|ruff|flake8|isort"
    [requirements.txt]="black|ruff|flake8"
)

# find_precommit_config <target> -> relative path, or empty
find_precommit_config() {
    local target="$1"
    for candidate in .pre-commit-config.yaml lefthook.yml .lefthook.yml; do
        if [[ -f "$target/$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# hooks_enforced_in_ci <target> -> 0/1
hooks_enforced_in_ci() {
    local target="$1"
    if [[ -f "$target/.pre-commit-config.yaml" ]] && rg -q 'ci:' "$target/.pre-commit-config.yaml" 2>/dev/null; then
        return 0
    fi
    if [[ -d "$target/.github/workflows" ]] \
        && rg -l -i 'pre-commit run|pre-commit\.ci|lefthook run' "$target/.github/workflows" 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: pre-commit.sh <target> [--fix]}"
    shift || true
    DO_FIX=false
    for arg in "$@"; do
        [[ "$arg" == "--fix" ]] && DO_FIX=true
    done
    export DO_FIX

    echo "== pre-commit ($target) =="

    local config_file
    config_file="$(find_precommit_config "$target" || true)"

    if [[ -z "$config_file" ]]; then
        report_fail "no .pre-commit-config.yaml or lefthook.yml found"
        echo "-- $FINDINGS_COUNT finding(s) --"
        return 0
    fi
    report_pass "pre-commit config found: $config_file"

    local config_content marker hint
    config_content="$(cat "$target/$config_file")"
    for marker in "${!ECOSYSTEM_HOOK_HINTS[@]}"; do
        if [[ -f "$target/$marker" ]]; then
            hint="${ECOSYSTEM_HOOK_HINTS[$marker]}"
            if grep -qiE "$hint" <<<"$config_content"; then
                report_pass "$marker ecosystem has a matching hook"
            else
                report_fail "$marker present but no matching hook in $config_file (expected one of: $hint)"
            fi
        fi
    done

    if hooks_enforced_in_ci "$target"; then
        report_pass "hooks enforced in CI (not just locally optional)"
    else
        report_fail "hooks not enforced in CI — only run if a contributor installed them locally" \
            "add a CI job running 'pre-commit run --all-files' (or enable pre-commit.ci)"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
