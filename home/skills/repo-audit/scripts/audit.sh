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

# Runs a check with the tools already on PATH when every package its
# `#!nix-shell -p` line names is there, and through that nix-shell otherwise.
# The first nix-shell in a cloud session fetches nixpkgs and ~260 MB of
# packages the image (plus the cloud kit) already has, and the image's gh is
# the one configured for its proxy.
run_check() {
    local script="$1"
    shift
    local deps pkg bin
    deps="$(sed -n '2s/^#!nix-shell -i bash -p //p' "$script")"
    if [[ -n "$deps" ]]; then
        for pkg in $deps; do
            bin="$pkg"
            [[ "$pkg" == ripgrep ]] && bin=rg
            if ! command -v "$bin" >/dev/null 2>&1; then
                "$script" "$@"
                return
            fi
        done
    fi
    bash "$script" "$@"
}

for topic in "${RUN_TOPICS[@]}"; do
    echo
    run_check "$SCRIPT_DIR/checks/$topic.sh" "$TARGET" "${PASSTHROUGH_ARGS[@]}" || true
done

echo
echo "audit of $TARGET complete."
