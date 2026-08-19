# shellcheck shell=bash
# Shared assertion + stub helpers for repo-audit's test files. Sourced by
# each tests/*.test.sh; not a test file itself, not run directly. Plain bash,
# no external test framework — matches scripts/tests/bootstrap-darwin.test.sh.

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

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    case "$haystack" in
        *"$needle"*)
            PASS=$((PASS + 1))
            ;;
        *)
            FAIL=$((FAIL + 1))
            FAILED_TESTS+=("$msg | expected to contain='$needle'")
            echo "FAIL: $msg"
            echo "  expected to contain: $needle"
            echo "  actual: $haystack"
            ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    case "$haystack" in
        *"$needle"*)
            FAIL=$((FAIL + 1))
            FAILED_TESTS+=("$msg | expected NOT to contain='$needle'")
            echo "FAIL: $msg"
            echo "  expected NOT to contain: $needle"
            echo "  actual: $haystack"
            ;;
        *)
            PASS=$((PASS + 1))
            ;;
    esac
}

# make_stub_dir -> path to a fresh dir for PATH-shadowing stub executables.
make_stub_dir() {
    mktemp -d
}

# stub <dir> <name> <body> — writes an executable `<dir>/<name>` running <body>.
stub() {
    local dir="$1" name="$2" body="$3"
    cat >"$dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$dir/$name"
}

# make_fixture_repo -> path to a fresh, git-initialized scratch repo (no
# remote, so forge_detect resolves it to FORGE=unknown unless overridden).
make_fixture_repo() {
    local dir
    dir="$(mktemp -d)"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "test"
    echo "$dir"
}

print_summary() {
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
    exit 0
}
