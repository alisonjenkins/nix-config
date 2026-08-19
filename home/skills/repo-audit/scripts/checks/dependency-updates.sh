#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash gh jq git
# shellcheck shell=bash
# Usage: dependency-updates.sh <target> [--fix] [--forge=github|gitlab]
#
# Checks: renovate.json/dependabot.yml present, covers detected ecosystems.
# Local-file check — see ../../dependency-updates.md.
#
# main() is guarded below so scripts/tests/dependency-updates.test.sh can
# source this file and call individual functions without running main.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/forge.sh
source "$SCRIPT_DIR/../lib/forge.sh"
# shellcheck source=../lib/report.sh
source "$SCRIPT_DIR/../lib/report.sh"

# Ecosystem coverage: presence-only heuristic, not a full parse of the config.
declare -A ECOSYSTEM_MARKERS=(
    [go.mod]="gomod"
    [package.json]="npm"
    [Cargo.toml]="cargo"
    [flake.nix]="nix"
    [requirements.txt]="pip"
    [pyproject.toml]="pip|poetry"
    [Dockerfile]="dockerfile|docker"
)

# find_dependency_config <target> -> relative path, or empty
find_dependency_config() {
    local target="$1"
    for candidate in renovate.json renovate.json5 .github/renovate.json .github/renovate.json5 .github/dependabot.yml; do
        if [[ -f "$target/$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

apply_scaffold_renovate() {
    local target="$1"
    echo "{\"\$schema\": \"https://docs.renovatebot.com/renovate-schema.json\", \"extends\": [\"config:recommended\"]}" \
        | jq . > "$target/renovate.json"
}

main() {
    set -euo pipefail
    FINDINGS_COUNT=0
    local target="${1:?usage: dependency-updates.sh <target> [--fix] [--forge=...]}"
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
    echo "== dependency-updates ($TARGET_REPO, forge=$FORGE) =="

    if [[ ! -d "$target/.git" ]]; then
        report_skip "dependency-updates check needs a local checkout, got: $target"
        return 0
    fi

    local config_file
    config_file="$(find_dependency_config "$target" || true)"

    if [[ -z "$config_file" ]]; then
        report_fail "no renovate.json or dependabot.yml found"
        confirm_fix "scaffold a minimal renovate.json (config:recommended)" apply_scaffold_renovate "$target"
    else
        report_pass "dependency-update config found: $config_file"

        local config_content marker keyword
        config_content="$(cat "$target/$config_file")"
        for marker in "${!ECOSYSTEM_MARKERS[@]}"; do
            if [[ -f "$target/$marker" ]]; then
                keyword="${ECOSYSTEM_MARKERS[$marker]}"
                if grep -qiE "$keyword" <<<"$config_content"; then
                    report_pass "$marker ecosystem covered by $config_file"
                else
                    report_fail "$marker present but not obviously covered by $config_file (manager: $keyword)"
                fi
            fi
        done
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
