#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git jq
# shellcheck shell=bash
# Unit tests for scripts/checks/dependency-updates.sh. Local-file check, no
# forge API calls — runs against real fixture directories, no stubs needed.
#
# Usage: ./dependency-updates.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/dependency-updates.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

test_find_dependency_config_missing() {
    local repo; repo="$(make_fixture_repo)"
    find_dependency_config "$repo" >/dev/null
    assert_exit 1 $? "find_dependency_config: returns 1 when no config present"
    rm -rf "$repo"
}

test_find_dependency_config_finds_renovate() {
    local repo; repo="$(make_fixture_repo)"
    echo '{}' > "$repo/renovate.json"
    local out
    out="$(find_dependency_config "$repo")"
    assert_eq "renovate.json" "$out" "find_dependency_config: finds root renovate.json"
    rm -rf "$repo"
}

test_find_dependency_config_finds_dependabot() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github"
    echo 'version: 2' > "$repo/.github/dependabot.yml"
    local out
    out="$(find_dependency_config "$repo")"
    assert_eq ".github/dependabot.yml" "$out" "find_dependency_config: finds .github/dependabot.yml"
    rm -rf "$repo"
}

test_main_reports_missing_config() {
    local repo; repo="$(make_fixture_repo)"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "no renovate.json or dependabot.yml found" "main: flags missing config"
    rm -rf "$repo"
}

test_main_reports_uncovered_ecosystem() {
    local repo; repo="$(make_fixture_repo)"
    echo '{"extends": ["config:recommended"], "packageRules": [{"matchManagers": ["npm"]}]}' > "$repo/renovate.json"
    touch "$repo/flake.nix"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "flake.nix present but not obviously covered" "main: flags an ecosystem the config doesn't mention"
    rm -rf "$repo"
}

test_main_passes_when_ecosystem_covered() {
    local repo; repo="$(make_fixture_repo)"
    echo '{"extends": ["config:recommended"], "nix": {"enabled": true}}' > "$repo/renovate.json"
    touch "$repo/flake.nix"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "flake.nix ecosystem covered by renovate.json" "main: passes when the config keyword matches"
    rm -rf "$repo"
}

test_main_skips_non_checkout_target() {
    local out
    out="$(main "/nonexistent/not-a-repo" 2>&1)"
    assert_contains "$out" "needs a local checkout" "main: skips (not fails) when target isn't a local checkout"
}

test_renovate_automerge_enabled_true_key() {
    renovate_automerge_enabled '{"automerge": true}'
    assert_exit 0 $? "renovate_automerge_enabled: detects explicit automerge:true"
}

test_renovate_automerge_enabled_preset() {
    renovate_automerge_enabled '{"extends": ["config:recommended", ":automergeAll"]}'
    assert_exit 0 $? "renovate_automerge_enabled: detects :automergeAll preset"
}

test_renovate_automerge_enabled_missing() {
    renovate_automerge_enabled '{"extends": ["config:recommended"]}'
    assert_exit 1 $? "renovate_automerge_enabled: returns 1 when neither is present"
}

test_main_flags_renovate_missing_automerge() {
    local repo; repo="$(make_fixture_repo)"
    echo '{"extends": ["config:recommended"]}' > "$repo/renovate.json"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "auto-merge not enabled" "main: flags renovate.json with no automerge as a hard finding"
    rm -rf "$repo"
}

test_main_passes_renovate_with_automerge() {
    local repo; repo="$(make_fixture_repo)"
    echo '{"extends": ["config:recommended"], "automerge": true}' > "$repo/renovate.json"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "auto-merge enabled" "main: passes renovate.json with automerge:true"
    rm -rf "$repo"
}

test_main_flags_dependabot_missing_automerge() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github"
    echo 'version: 2' > "$repo/.github/dependabot.yml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "auto-merge not enabled" "main: flags dependabot.yml with no auto-merge workflow"
    rm -rf "$repo"
}

test_main_passes_dependabot_with_automerge_workflow() {
    local repo; repo="$(make_fixture_repo)"
    mkdir -p "$repo/.github/workflows"
    echo 'version: 2' > "$repo/.github/dependabot.yml"
    echo 'uses: dependabot/fetch-metadata@v2' > "$repo/.github/workflows/automerge.yaml"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "auto-merge enabled" "main: passes dependabot.yml with a fetch-metadata automerge workflow"
    rm -rf "$repo"
}

test_fix_enables_renovate_automerge_on_confirm() {
    local repo; repo="$(make_fixture_repo)"
    echo '{"extends": ["config:recommended"]}' > "$repo/renovate.json"
    echo y | main "$repo" --fix >/dev/null 2>&1
    local automerge
    automerge="$(jq -r '.automerge' "$repo/renovate.json")"
    assert_eq "true" "$automerge" "main --fix: sets automerge:true in an existing renovate.json when confirmed"
    rm -rf "$repo"
}

test_fix_scaffolds_renovate_on_confirm() {
    local repo; repo="$(make_fixture_repo)"
    echo y | main "$repo" --fix >/dev/null 2>&1
    assert_eq "1" "$([ -f "$repo/renovate.json" ] && echo 1 || echo 0)" "main --fix: scaffolds renovate.json when confirmed"
    rm -rf "$repo"
}

test_fix_does_not_scaffold_on_decline() {
    local repo; repo="$(make_fixture_repo)"
    echo n | main "$repo" --fix >/dev/null 2>&1
    assert_eq "0" "$([ -f "$repo/renovate.json" ] && echo 1 || echo 0)" "main --fix: does not scaffold when declined"
    rm -rf "$repo"
}

run_all() {
    test_find_dependency_config_missing
    test_find_dependency_config_finds_renovate
    test_find_dependency_config_finds_dependabot
    test_main_reports_missing_config
    test_main_reports_uncovered_ecosystem
    test_main_passes_when_ecosystem_covered
    test_main_skips_non_checkout_target
    test_renovate_automerge_enabled_true_key
    test_renovate_automerge_enabled_preset
    test_renovate_automerge_enabled_missing
    test_main_flags_renovate_missing_automerge
    test_main_passes_renovate_with_automerge
    test_main_flags_dependabot_missing_automerge
    test_main_passes_dependabot_with_automerge_workflow
    test_fix_enables_renovate_automerge_on_confirm
    test_fix_scaffolds_renovate_on_confirm
    test_fix_does_not_scaffold_on_decline
}

run_all
print_summary
