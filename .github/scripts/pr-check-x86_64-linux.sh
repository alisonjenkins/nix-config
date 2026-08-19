#!/usr/bin/env bash
# Lightweight PR sanity check: reusable flake outputs only — nixosModules,
# homeModules, overlays, devShells, packages. Deliberately does NOT touch
# nixosConfigurations/homeConfigurations (whole-host configs): evaluating
# even one desktop host's full toplevel took several minutes and building it
# queues 1000+ derivations, both far too slow for a per-PR gate. Host config
# breakage still gets caught on push via build-and-cache.yaml — this only
# needs to catch a broken module/package/devShell before a dependency bump
# merges unattended.
#
# Usage: pr-check-x86_64-linux.sh
set -uo pipefail

TARGET_SYSTEM="x86_64-linux"
FAILED=0

# check_module_set <flake-attr> — every entry must be a function or attrset,
# matching the same isFunctionOrAttrs check `nix flake check` runs on
# nixosModules/homeModules.
check_module_set() {
    local flake_attr="$1"
    local names name
    names="$(nix eval --json "${flake_attr}" --apply builtins.attrNames 2>/dev/null | jq -r '.[]' || true)"
    for name in $names; do
        if nix eval --no-warn-dirty "${flake_attr}.${name}" \
            --apply 'x: if builtins.isFunction x || builtins.isAttrs x then "ok" else throw "neither a function nor an attrset"' \
            >/dev/null 2>&1; then
            echo "ok: ${flake_attr}.${name}"
        else
            echo "FAILED: ${flake_attr}.${name}"
            FAILED=1
        fi
    done
}

# check_drv_set <flake-attr> — every entry must evaluate to a derivation
# (drvPath), not built.
check_drv_set() {
    local flake_attr="$1"
    local names name
    names="$(nix eval --json "${flake_attr}" --apply builtins.attrNames 2>/dev/null | jq -r '.[]' || true)"
    for name in $names; do
        if nix eval --raw --no-warn-dirty "${flake_attr}.${name}.drvPath" >/dev/null 2>&1; then
            echo "ok: ${flake_attr}.${name}"
        else
            echo "FAILED: ${flake_attr}.${name}"
            nix eval --raw --no-warn-dirty "${flake_attr}.${name}.drvPath" 2>&1 | tail -20
            FAILED=1
        fi
    done
}

echo "== nixosModules =="
check_module_set ".#nixosModules"

echo "== homeModules =="
check_module_set ".#homeModules"

echo "== overlays =="
check_module_set ".#overlays"

echo "== devShells.${TARGET_SYSTEM} =="
check_drv_set ".#devShells.${TARGET_SYSTEM}"

echo "== packages.${TARGET_SYSTEM} =="
check_drv_set ".#packages.${TARGET_SYSTEM}"

exit "$FAILED"
