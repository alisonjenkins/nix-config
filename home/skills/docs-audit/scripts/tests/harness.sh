# shellcheck shell=bash
# Shared assertion helpers for docs-audit test files.

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

make_fixture_repo() {
    local dir
    dir="$(mktemp -d)"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "test"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config tag.gpgsign false
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
