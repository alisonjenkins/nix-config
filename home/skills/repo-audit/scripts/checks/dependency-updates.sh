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
    echo "{\"\$schema\": \"https://docs.renovatebot.com/renovate-schema.json\", \"extends\": [\"config:recommended\", \":automergeAll\"]}" \
        | jq . > "$target/renovate.json"
}

# renovate_automerge_enabled <config-content> -> 0/1
# Matches an explicit "automerge": true, or one of Renovate's automerge
# presets pulled in via "extends".
renovate_automerge_enabled() {
    local content="$1"
    grep -qiE '"automerge"[[:space:]]*:[[:space:]]*true' <<<"$content" && return 0
    grep -qiE ':automerge(all|patch|minor)?"' <<<"$content" && return 0
    return 1
}

apply_enable_renovate_automerge() {
    local target="$1" config_file="$2"
    jq '.automerge = true' "$target/$config_file" > "$target/$config_file.tmp" \
        && mv "$target/$config_file.tmp" "$target/$config_file"
}

# dependabot_automerge_enabled <target> -> 0/1
# Dependabot itself has no automerge key — the standard pattern is a
# workflow using dependabot/fetch-metadata + `gh pr merge --auto`.
dependabot_automerge_enabled() {
    local target="$1"
    [[ -d "$target/.github/workflows" ]] \
        && grep -qriE 'dependabot/fetch-metadata|pr merge --auto|enable-automerge' "$target/.github/workflows" 2>/dev/null
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

        case "$config_file" in
            renovate.json|renovate.json5|.github/renovate.json|.github/renovate.json5)
                if renovate_automerge_enabled "$config_content"; then
                    report_pass "auto-merge enabled (required for dependency updates to scale)"
                else
                    report_fail "auto-merge not enabled — required, not a per-repo judgment call" \
                        "add \"automerge\": true, or extend \":automergeAll\"; only merges safely once required status checks are set (see branch-protection.md)"
                    confirm_fix "enable automerge in $config_file" apply_enable_renovate_automerge "$target" "$config_file"
                fi
                ;;
            .github/dependabot.yml)
                if dependabot_automerge_enabled "$target"; then
                    report_pass "auto-merge enabled (dependabot/fetch-metadata + auto-merge workflow found)"
                else
                    report_fail "auto-merge not enabled — required, not a per-repo judgment call" \
                        "add a workflow using dependabot/fetch-metadata + 'gh pr merge --auto' (or GitHub's native auto-merge) gated on required status checks"
                fi
                ;;
        esac
    fi

    echo "-- $FINDINGS_COUNT finding(s) --"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
