#!/usr/bin/env bash
# Runs every tests/*.test.sh and reports a combined pass/fail summary.
#
# Usage: ./run-all.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=()

for t in "$TESTS_DIR"/*.test.sh; do
    echo "== $(basename "$t") =="
    if ! "$t"; then
        FAILED+=("$(basename "$t")")
    fi
    echo
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED: ${FAILED[*]}"
    exit 1
fi
echo "all test files passed."
