#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash nix git ripgrep
# shellcheck shell=bash
# Usage: dev-shell.sh <target> [--fix]
#
# Local-repo-only, no forge API. Checks flake.nix devShells + packages,
# .envrc, and onboarding docs. See ../../dev-shell.md.
#
# main() is guarded below so scripts/tests/dev-shell.test.sh can source this
# file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

apply_scaffold_envrc() {
    local target="$1"
    echo "use flake" > "$target/.envrc"
}

# detect_system -> "x86_64-linux" etc, falls back on eval failure
detect_system() {
    nix eval --raw --impure --expr 'builtins.currentSystem' 2>/dev/null || echo "x86_64-linux"
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: dev-shell.sh <target> [--fix]}"
    shift || true
    DO_FIX=false
    for arg in "$@"; do
        [[ "$arg" == "--fix" ]] && DO_FIX=true
    done
    export DO_FIX

    echo "== dev-shell ($target) =="

    if [[ ! -f "$target/flake.nix" ]]; then
        report_fail "no flake.nix found — Nix packaging is the house standard for dev shell + build"
        echo "-- $FINDINGS_COUNT finding(s) --"
        return 0
    fi
    report_pass "flake.nix present"

    local system
    system="$(detect_system)"

    if nix eval --no-warn-dirty "$target#devShells.$system.default" >/dev/null 2>&1; then
        report_pass "devShells.$system.default exists"
    else
        report_fail "no devShells.$system.default in flake.nix"
    fi

    if nix eval --no-warn-dirty "$target#packages.$system.default" >/dev/null 2>&1; then
        report_pass "packages.$system.default exists"
        if nix build --no-link "$target#packages.$system.default" 2>/dev/null; then
            report_pass "packages.$system.default builds successfully"
        else
            report_fail "packages.$system.default exists but 'nix build' fails"
        fi
    else
        report_fail "no packages.$system.default in flake.nix — same flake should build the repo's software, not just provide a dev shell"
    fi

    if [[ -f "$target/.envrc" ]] && grep -qE '^use (flake|nix)|nix print-dev-env|nix develop' "$target/.envrc"; then
        report_pass ".envrc present and wires up the flake dev shell"
    else
        report_fail "no .envrc found (or it doesn't wire up the flake dev shell)"
        confirm_fix "scaffold .envrc with 'use flake'" apply_scaffold_envrc "$target"
    fi

    if rg -qi 'direnv allow' "$target/README.md" "$target/CONTRIBUTING.md" 2>/dev/null; then
        report_pass "onboarding docs mention 'direnv allow'"
    else
        report_fail "README/CONTRIBUTING don't mention 'direnv allow'"
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
