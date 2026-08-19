#!/usr/bin/env bash
# Unit tests for scripts/lib/report.sh — finding counters and the
# confirm_fix confirmation gate (never applies without an explicit "y").
#
# Usage: ./report.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TESTS_DIR/../lib" && pwd)"

# shellcheck source=./harness.sh
. "$TESTS_DIR/harness.sh"
# shellcheck source=../lib/report.sh
. "$LIB_DIR/report.sh"

test_report_pass_does_not_increment_findings() {
    FINDINGS_COUNT=0
    report_pass "ok" >/dev/null
    assert_eq "0" "$FINDINGS_COUNT" "report_pass leaves FINDINGS_COUNT unchanged"
}

test_report_fail_increments_findings() {
    FINDINGS_COUNT=0
    report_fail "bad" >/dev/null
    report_fail "also bad" >/dev/null
    assert_eq "2" "$FINDINGS_COUNT" "report_fail increments FINDINGS_COUNT once per call"
}

test_report_skip_does_not_increment_findings() {
    FINDINGS_COUNT=0
    report_skip "n/a" >/dev/null
    assert_eq "0" "$FINDINGS_COUNT" "report_skip leaves FINDINGS_COUNT unchanged"
}

test_confirm_fix_noop_when_do_fix_false() {
    DO_FIX=false
    local called=0
    mark_called() { called=1; }
    confirm_fix "do the thing" mark_called >/dev/null
    assert_eq "0" "$called" "confirm_fix: no-op (no prompt, no apply) when DO_FIX=false"
}

test_confirm_fix_skips_on_no() {
    DO_FIX=true
    local called=0
    mark_called() { called=1; }
    confirm_fix "do the thing" mark_called >/dev/null <<<"n"
    assert_eq "0" "$called" "confirm_fix: answering 'n' does not call the apply function"
}

test_confirm_fix_applies_on_yes() {
    DO_FIX=true
    local called=0
    mark_called() { called=1; }
    confirm_fix "do the thing" mark_called >/dev/null <<<"y"
    assert_eq "1" "$called" "confirm_fix: answering 'y' calls the apply function"
}

test_confirm_fix_passes_through_extra_args() {
    DO_FIX=true
    local seen_args=""
    capture_args() { seen_args="$*"; }
    confirm_fix "do the thing" capture_args "arg1" "arg2" >/dev/null <<<"y"
    assert_eq "arg1 arg2" "$seen_args" "confirm_fix: extra args after the apply-fn are forwarded to it"
}

run_all() {
    test_report_pass_does_not_increment_findings
    test_report_fail_increments_findings
    test_report_skip_does_not_increment_findings
    test_confirm_fix_noop_when_do_fix_false
    test_confirm_fix_skips_on_no
    test_confirm_fix_applies_on_yes
    test_confirm_fix_passes_through_extra_args
}

run_all
print_summary
