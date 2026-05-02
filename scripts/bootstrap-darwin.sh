#!/usr/bin/env bash
# Bootstrap Nix + nix-darwin on a fresh macOS machine.
#
# Run from the root of this nix-config repo. Installs Nix (if missing),
# detects the machine hostname, and applies the matching darwinConfiguration
# from the flake.
#
# Idempotent: every step is gated on a "is this already done?" check so a
# re-run after a partial failure picks up where it stopped.
#
# Usage:
#   ./scripts/bootstrap-darwin.sh

NIX_DAEMON_PROFILE="${NIX_DAEMON_PROFILE:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
NIX_DARWIN_REF="${NIX_DARWIN_REF:-github:lnl7/nix-darwin/nix-darwin-25.11}"

check_platform() {
    if [ "$(uname)" != "Darwin" ]; then
        echo "Error: this script is for macOS only (uname=$(uname))." >&2
        return 1
    fi
}

check_repo_root() {
    if [ ! -f "./flake.nix" ]; then
        echo "Error: must be run from the nix-config repo root (no flake.nix in $(pwd))." >&2
        return 1
    fi
}

nix_installed() {
    command -v nix >/dev/null 2>&1 || [ -f "$NIX_DAEMON_PROFILE" ]
}

install_nix() {
    if nix_installed; then
        echo "==> Nix already installed, skipping installer."
        return 0
    fi
    echo "==> Installing Nix (multi-user, official installer)..."
    sh <(curl -L https://nixos.org/nix/install) --daemon
}

source_nix_profile() {
    if [ -f "$NIX_DAEMON_PROFILE" ]; then
        # shellcheck disable=SC1090
        . "$NIX_DAEMON_PROFILE"
    fi
}

detect_hostname() {
    scutil --get LocalHostName 2>/dev/null || hostname -s
}

available_darwin_hosts() {
    nix --extra-experimental-features 'nix-command flakes' eval --json \
        '.#darwinConfigurations' --apply 'builtins.attrNames' \
        | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}

host_matches() {
    local host="$1" available="$2"
    grep -Fxq "$host" <<<"$available"
}

apply_config() {
    local host="$1"
    if command -v darwin-rebuild >/dev/null 2>&1; then
        echo "==> darwin-rebuild present, switching to .#$host..."
        sudo darwin-rebuild switch --flake ".#$host"
    else
        echo "==> First-time bootstrap: running nix-darwin from $NIX_DARWIN_REF..."
        sudo nix --extra-experimental-features 'nix-command flakes' \
            run "$NIX_DARWIN_REF" -- switch --flake ".#$host"
    fi
}

main() {
    set -euo pipefail

    check_platform
    check_repo_root
    install_nix
    source_nix_profile

    if ! command -v nix >/dev/null 2>&1; then
        echo "Error: nix still not on PATH after sourcing $NIX_DAEMON_PROFILE." >&2
        exit 1
    fi

    local host
    host="$(detect_hostname)"
    echo "==> Detected hostname: $host"

    echo "==> Looking up darwinConfigurations in flake..."
    local available
    available="$(available_darwin_hosts)"

    if ! host_matches "$host" "$available"; then
        echo "Error: no darwinConfigurations.\"$host\" found in flake." >&2
        echo "Available hosts:" >&2
        echo "$available" | sed 's/^/  - /' >&2
        echo >&2
        echo "Either rename this Mac (sudo scutil --set LocalHostName <name>) or add a host config." >&2
        exit 1
    fi

    apply_config "$host"

    echo
    echo "==> Done. Future rebuilds: just switch"
}

# Only run main when executed directly, not when sourced (e.g. by tests).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
