#!/usr/bin/env bash
set -euo pipefail
# Entrypoint: runs one or all repo-audit checks against a target repo.
#
# Usage: audit.sh <target> [topic] [--fix] [--forge=github|gitlab]
#   <target>: local path or owner/repo
#   [topic]:  branch-protection | secret-scanning | dependency-updates |
#             ci-pipeline | release-management | pre-commit | dev-shell
#             (omit to run all seven)
#   --fix:    prompt to apply each finding individually; default is
#             report-only and mutates nothing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOPICS=(branch-protection secret-scanning dependency-updates ci-pipeline release-management pre-commit dev-shell)

usage() {
    echo "usage: audit.sh <target> [topic] [--fix] [--forge=github|gitlab]"
    echo "topics: ${TOPICS[*]}"
    exit 1
}

[[ $# -ge 1 ]] || usage
TARGET="$1"
shift

REQUESTED_TOPIC=""
PASSTHROUGH_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --fix|--forge=*) PASSTHROUGH_ARGS+=("$arg") ;;
        -h|--help) usage ;;
        *)
            if [[ " ${TOPICS[*]} " == *" $arg "* ]]; then
                REQUESTED_TOPIC="$arg"
            else
                echo "unknown topic or flag: $arg" >&2
                usage
            fi
            ;;
    esac
done

RUN_TOPICS=("${TOPICS[@]}")
[[ -n "$REQUESTED_TOPIC" ]] && RUN_TOPICS=("$REQUESTED_TOPIC")

for topic in "${RUN_TOPICS[@]}"; do
    echo
    "$SCRIPT_DIR/checks/$topic.sh" "$TARGET" "${PASSTHROUGH_ARGS[@]}" || true
done

echo
echo "audit of $TARGET complete."
