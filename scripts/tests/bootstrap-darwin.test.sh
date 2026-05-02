#!/usr/bin/env bash
# Unit tests for scripts/bootstrap-darwin.sh.
#
# Strategy: source the script (main is guarded so it won't run), then mock
# external commands (scutil, hostname, nix, sudo, darwin-rebuild, uname) by
# putting stubs on PATH. Each test asserts a single function's behavior.
#
# Usage:
#   ./scripts/tests/bootstrap-darwin.test.sh
#
# No external deps (no bats). Plain bash, returns non-zero on first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$SCRIPT_DIR/bootstrap-darwin.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$msg | expected='$expected' actual='$actual'")
        echo "FAIL: $msg"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

assert_exit() {
    local expected_rc="$1" actual_rc="$2" msg="${3:-}"
    if [ "$expected_rc" = "$actual_rc" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$msg | expected_rc=$expected_rc actual_rc=$actual_rc")
        echo "FAIL: $msg (expected rc=$expected_rc, got $actual_rc)"
    fi
}

# Build a temp dir of stub executables on PATH. Each call resets stubs.
make_stub_dir() {
    local dir
    dir="$(mktemp -d)"
    echo "$dir"
}

stub() {
    # stub <dir> <name> <body>
    local dir="$1" name="$2" body="$3"
    cat >"$dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$dir/$name"
}

# Source the target. Strip `set -euo pipefail` from main path: we source it
# but we don't call main, so the top-level `set` lives only inside main.
# shellcheck source=/dev/null
. "$TARGET"

# ---------- detect_hostname ----------

test_detect_hostname_prefers_scutil() {
    local d; d="$(make_stub_dir)"
    stub "$d" scutil 'echo "scutil-host"'
    stub "$d" hostname 'echo "hostname-host"'
    local out
    out="$(PATH="$d:$PATH" detect_hostname)"
    assert_eq "scutil-host" "$out" "detect_hostname prefers scutil"
    rm -rf "$d"
}

test_detect_hostname_falls_back_to_hostname() {
    local d; d="$(make_stub_dir)"
    stub "$d" scutil 'exit 1'
    stub "$d" hostname 'echo "hostname-host"'
    local out
    out="$(PATH="$d:$PATH" detect_hostname)"
    assert_eq "hostname-host" "$out" "detect_hostname falls back to hostname -s"
    rm -rf "$d"
}

# ---------- host_matches ----------

test_host_matches_hit() {
    host_matches "ali-mba" $'ali-mba\nAlisons-MacBook-Pro'
    assert_exit 0 $? "host_matches returns 0 on exact match"
}

test_host_matches_miss() {
    host_matches "bogus" $'ali-mba\nAlisons-MacBook-Pro'
    assert_exit 1 $? "host_matches returns 1 on miss"
}

test_host_matches_no_substring() {
    # Substring of an entry must NOT match — grep -Fxq is full-line.
    host_matches "mba" $'ali-mba\nAlisons-MacBook-Pro'
    assert_exit 1 $? "host_matches rejects substring (full-line only)"
}

test_host_matches_handles_special_chars() {
    # Hyphenated names should match literally, not be treated as regex.
    host_matches "Alisons-MacBook-Pro" $'ali-mba\nAlisons-MacBook-Pro'
    assert_exit 0 $? "host_matches treats input as literal (hyphens fine)"
}

# ---------- available_darwin_hosts ----------

test_available_darwin_hosts_parses_nix_output() {
    local d; d="$(make_stub_dir)"
    # Simulate `nix eval --json` returning a JSON array.
    stub "$d" nix 'echo "[\"ali-mba\",\"Alisons-MacBook-Pro\"]"'
    local out
    out="$(PATH="$d:$PATH" available_darwin_hosts)"
    local expected=$'ali-mba\nAlisons-MacBook-Pro'
    assert_eq "$expected" "$out" "available_darwin_hosts parses JSON array into newline list"
    rm -rf "$d"
}

test_available_darwin_hosts_empty() {
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'echo "[]"'
    local out
    out="$(PATH="$d:$PATH" available_darwin_hosts)"
    assert_eq "" "$out" "available_darwin_hosts returns empty for empty array"
    rm -rf "$d"
}

# ---------- nix_installed gating (idempotency) ----------

test_nix_installed_true_when_command_present() {
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'true'
    NIX_DAEMON_PROFILE="/nonexistent" PATH="$d:$PATH" nix_installed
    assert_exit 0 $? "nix_installed: true when nix on PATH"
    rm -rf "$d"
}

test_nix_installed_true_when_profile_present() {
    local d; d="$(make_stub_dir)"
    local profile; profile="$(mktemp)"
    # Empty PATH so `command -v nix` fails (need to keep some basics).
    PATH="$d" NIX_DAEMON_PROFILE="$profile" nix_installed
    assert_exit 0 $? "nix_installed: true when daemon profile exists"
    rm -f "$profile"
    rm -rf "$d"
}

test_nix_installed_false_when_neither() {
    local d; d="$(make_stub_dir)"
    PATH="$d" NIX_DAEMON_PROFILE="/nonexistent" nix_installed
    assert_exit 1 $? "nix_installed: false when neither nix nor profile exists"
    rm -rf "$d"
}

test_install_nix_skips_when_already_installed() {
    local d; d="$(make_stub_dir)"
    stub "$d" nix 'true'
    # If install_nix tried to actually run the curl pipeline, this would
    # block / fail. The skip path just echoes and returns.
    local out
    out="$(NIX_DAEMON_PROFILE="/nonexistent" PATH="$d:$PATH" install_nix)"
    assert_eq "==> Nix already installed, skipping installer." "$out" \
        "install_nix is idempotent: skips when nix already present"
    rm -rf "$d"
}

# ---------- check_platform / check_repo_root ----------

test_check_platform_rejects_non_darwin() {
    local d; d="$(make_stub_dir)"
    stub "$d" uname 'echo "Linux"'
    PATH="$d:$PATH" check_platform 2>/dev/null
    assert_exit 1 $? "check_platform rejects non-Darwin"
    rm -rf "$d"
}

test_check_platform_accepts_darwin() {
    local d; d="$(make_stub_dir)"
    stub "$d" uname 'echo "Darwin"'
    PATH="$d:$PATH" check_platform
    assert_exit 0 $? "check_platform accepts Darwin"
    rm -rf "$d"
}

test_check_repo_root_rejects_non_repo() {
    local d; d="$(mktemp -d)"
    (cd "$d" && check_repo_root) 2>/dev/null
    assert_exit 1 $? "check_repo_root rejects dir without flake.nix"
    rm -rf "$d"
}

test_check_repo_root_accepts_repo() {
    (cd "$REPO_ROOT" && check_repo_root)
    assert_exit 0 $? "check_repo_root accepts repo root (has flake.nix)"
}

# ---------- run all ----------

run_all() {
    test_detect_hostname_prefers_scutil
    test_detect_hostname_falls_back_to_hostname
    test_host_matches_hit
    test_host_matches_miss
    test_host_matches_no_substring
    test_host_matches_handles_special_chars
    test_available_darwin_hosts_parses_nix_output
    test_available_darwin_hosts_empty
    test_nix_installed_true_when_command_present
    test_nix_installed_true_when_profile_present
    test_nix_installed_false_when_neither
    test_install_nix_skips_when_already_installed
    test_check_platform_rejects_non_darwin
    test_check_platform_accepts_darwin
    test_check_repo_root_rejects_non_repo
    test_check_repo_root_accepts_repo
}

run_all

echo
echo "============================="
echo "Passed: $PASS  Failed: $FAIL"
echo "============================="

if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
