#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git ripgrep
# shellcheck shell=bash
# Unit tests for scripts/checks/dev-shell.sh. `nix` is stubbed (real
# eval/build in a fixture dir with no real flake would be slow/misleading) —
# everything else runs against real fixture files.
#
# Usage: ./dev-shell.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$TESTS_DIR/../checks/dev-shell.sh"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=/dev/null
. "$TARGET"

test_main_flags_missing_flake() {
    local repo; repo="$(make_fixture_repo)"
    local out
    out="$(main "$repo" 2>&1)"
    assert_contains "$out" "no flake.nix found" "main: flags a repo with no flake.nix at all"
    rm -rf "$repo"
}

test_main_flags_missing_devshell_and_package() {
    local repo; repo="$(make_fixture_repo)"
    touch "$repo/flake.nix"
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'exit 1' # every `nix eval`/`nix build` call fails
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "no devShells" "main: flags missing devShells output"
    assert_contains "$out" "no packages" "main: flags missing packages output"
    rm -rf "$repo" "$d"
}

test_main_passes_devshell_and_package_when_both_present() {
    local repo; repo="$(make_fixture_repo)"
    touch "$repo/flake.nix"
    echo "use flake" > "$repo/.envrc"
    echo "direnv allow" > "$repo/README.md"
    local d; d="$(make_stub_dir)"
    stub "$d" nix '
        case "$*" in
            *currentSystem*) echo "x86_64-linux" ;;
            *) exit 0 ;; # eval devShells/packages + build --no-link: all succeed
        esac
    '
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" "devShells.x86_64-linux.default exists" "main: passes when devShells eval succeeds"
    assert_contains "$out" "packages.x86_64-linux.default exists" "main: passes when packages eval succeeds"
    assert_contains "$out" "packages.x86_64-linux.default builds successfully" "main: passes when nix build succeeds"
    assert_contains "$out" ".envrc present and wires up the flake dev shell" "main: passes on a plain 'use flake' .envrc"
    assert_contains "$out" "onboarding docs mention 'direnv allow'" "main: passes when README mentions direnv allow"
    rm -rf "$repo" "$d"
}

test_main_accepts_hand_rolled_envrc() {
    # Regression: this repo's own .envrc skips `use flake` for a hand-rolled
    # `nix print-dev-env` — must not be flagged as missing.
    local repo; repo="$(make_fixture_repo)"
    touch "$repo/flake.nix"
    printf 'watch_file flake.nix\nrc=$(nix print-dev-env .)\neval "$rc"\n' > "$repo/.envrc"
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'exit 1'
    local out
    out="$(PATH="$d:$PATH" main "$repo" 2>&1)"
    assert_contains "$out" ".envrc present and wires up the flake dev shell" "main: recognizes a hand-rolled 'nix print-dev-env' .envrc"
    rm -rf "$repo" "$d"
}

test_fix_scaffolds_envrc_on_confirm() {
    local repo; repo="$(make_fixture_repo)"
    touch "$repo/flake.nix"
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'exit 1'
    echo y | PATH="$d:$PATH" main "$repo" --fix >/dev/null 2>&1
    assert_eq "1" "$([ -f "$repo/.envrc" ] && echo 1 || echo 0)" "main --fix: scaffolds .envrc when confirmed"
    rm -rf "$repo" "$d"
}

run_all() {
    test_main_flags_missing_flake
    test_main_flags_missing_devshell_and_package
    test_main_passes_devshell_and_package_when_both_present
    test_main_accepts_hand_rolled_envrc
    test_fix_scaffolds_envrc_on_confirm
}

run_all
print_summary
