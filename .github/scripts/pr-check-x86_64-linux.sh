#!/usr/bin/env bash
# Lightweight PR sanity check: reusable flake outputs only — nixosModules,
# homeModules, overlays, devShells, packages. Deliberately does NOT touch
# nixosConfigurations/homeConfigurations (whole-host configs): evaluating
# even one desktop host's full toplevel took several minutes and building it
# queues 1000+ derivations, both far too slow for a per-PR gate. Host config
# breakage still gets caught on push via build-and-cache.yaml — this only
# needs to catch a broken module/package/devShell before a dependency bump
# merges unattended. Packages are evaluated, and the ones the PR changes are
# also built (build_changed_packages).
#
# Usage: pr-check-x86_64-linux.sh
set -uo pipefail

TARGET_SYSTEM="x86_64-linux"
FAILED=0
# Too heavy to build inside the PR check's 30 minutes; build-and-cache.yaml
# builds them on push.
SKIP_BUILD="camoufox-browser nvidia-kernel-canary"

# list_attr_names <flake-attr> — one attribute name per line, non-zero when
# the set cannot be evaluated. Callers must fail on that: treating it as an
# empty set passed the check with nothing checked.
list_attr_names() {
    nix eval --json "$1" --apply builtins.attrNames | jq -r '.[]'
}

# build_changed_packages <flake-attr> — build every exposed package whose
# pkgs/<name>/ directory differs from the base branch. Evaluation alone
# cannot catch a stale dependency hash (npmDepsHash, vendorHash) or a
# Cargo.lock behind its Cargo.toml: Renovate bumps the lockfile, the
# derivation still evaluates, and only the build fails. That merged
# unattended three times (cavemem #370, containerd-prepopulate #374, sift
# #256/#360) before this existed.
build_changed_packages() {
    local flake_attr="$1"
    local base="${GITHUB_BASE_REF:-main}"
    local exposed changed name
    if ! git fetch --no-tags --depth=1 origin "${base}" >/dev/null 2>&1; then
        echo "FAILED: could not fetch origin/${base} to find changed packages"
        FAILED=1
        return
    fi
    if ! exposed="$(list_attr_names "${flake_attr}")"; then
        echo "FAILED: could not list ${flake_attr}"
        FAILED=1
        return
    fi
    changed="$(git diff --name-only FETCH_HEAD HEAD -- pkgs | cut -d/ -f2 | sort -u)"
    for name in $changed; do
        if ! grep -qx "${name}" <<<"${exposed}"; then
            echo "not exposed, skipped: pkgs/${name}"
            continue
        fi
        case " ${SKIP_BUILD} " in
            *" ${name} "*)
                echo "too heavy, skipped: ${flake_attr}.${name}"
                continue
                ;;
        esac
        if nix build --no-link --no-warn-dirty "${flake_attr}.${name}"; then
            echo "built: ${flake_attr}.${name}"
        else
            echo "FAILED: ${flake_attr}.${name} does not build"
            FAILED=1
        fi
    done
}

# check_module_set <flake-attr> — every entry must be a function or attrset,
# matching the same isFunctionOrAttrs check `nix flake check` runs on
# nixosModules/homeModules.
check_module_set() {
    local flake_attr="$1"
    local names name
    if ! names="$(list_attr_names "${flake_attr}")"; then
        echo "FAILED: could not list ${flake_attr}"
        FAILED=1
        return
    fi
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
    if ! names="$(list_attr_names "${flake_attr}")"; then
        echo "FAILED: could not list ${flake_attr}"
        FAILED=1
        return
    fi
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

echo "== packages.${TARGET_SYSTEM} changed by this PR (built) =="
build_changed_packages ".#packages.${TARGET_SYSTEM}"

exit "$FAILED"
