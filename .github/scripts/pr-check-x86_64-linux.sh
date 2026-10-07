#!/usr/bin/env bash
# Lightweight PR sanity check: reusable flake outputs only — nixosModules,
# homeModules, overlays, devShells, packages. Deliberately does NOT touch
# nixosConfigurations/homeConfigurations (whole-host configs): evaluating
# even one desktop host's full toplevel took several minutes and building it
# queues 1000+ derivations, both far too slow for a per-PR gate. Host config
# breakage still gets caught on push via build-and-cache.yaml — this only
# needs to catch a broken module/package/devShell before a dependency bump
# merges unattended. Packages are evaluated, and the ones the PR changes are
# also built (build_changed_packages). aarch64-linux hosts are the one
# exception: they are evaluated here (check_hosts_for_system), since nothing
# else covers them.
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
    # --depth rewrites .git/shallow, so only use it where the checkout already
    # is shallow (CI); in a full clone it would break merge-base and rebases.
    local depth=()
    if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
        depth=(--depth=1)
    fi
    if ! git fetch --no-tags "${depth[@]}" origin "${base}" >/dev/null 2>&1; then
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
    # One eval for the whole set (a process per entry re-pays startup and
    # re-evaluates shared inputs); only on failure fall back to per-entry
    # evals to find which entry broke.
    if nix eval --raw --no-warn-dirty "${flake_attr}" \
        --apply 'ps: builtins.deepSeq (builtins.mapAttrs (_: p: p.drvPath) ps) "ok"' \
        >/dev/null 2>&1; then
        echo "ok: ${flake_attr} ($(wc -w <<<"${names}") entries, batched)"
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

# check_hosts_for_system <system> — evaluate (not build) the toplevel of every
# nixosConfiguration whose hostPlatform is <system>. The exception to "no
# whole-host configs" above: nothing else evaluates aarch64-linux hosts (the
# arm64 job in build-and-cache.yaml is disabled), so a flake.lock bump broke
# ali-mba-linux and dev-vm on main unnoticed. The desktop-sized ones take
# ~25s each; the server images far less.
# --max-jobs 0 because this x86 runner cannot build aarch64 derivations: any
# import-from-derivation must be substitutable, and one that is not fails
# here rather than silently needing binfmt.
check_hosts_for_system() {
    local system="$1"
    local names name
    if ! names="$(nix eval --json --no-warn-dirty .#nixosConfigurations \
        --apply "cs: builtins.filter (n: cs.\${n}.pkgs.stdenv.hostPlatform.system == \"${system}\") (builtins.attrNames cs)" \
        | jq -r '.[]')"; then
        echo "FAILED: could not list ${system} nixosConfigurations"
        FAILED=1
        return
    fi
    local nix_list="["
    for name in $names; do
        nix_list+=" \"${name}\""
    done
    nix_list+=" ]"
    if nix eval --raw --no-warn-dirty --max-jobs 0 .#nixosConfigurations \
        --apply "cs: builtins.deepSeq (map (n: cs.\${n}.config.system.build.toplevel.drvPath) ${nix_list}) \"ok\"" \
        >/dev/null 2>&1; then
        echo "ok: ${system} nixosConfigurations ($(wc -w <<<"${names}") hosts, batched)"
        return
    fi
    for name in $names; do
        local attr=".#nixosConfigurations.${name}.config.system.build.toplevel.drvPath"
        if nix eval --raw --no-warn-dirty --max-jobs 0 "${attr}" >/dev/null 2>&1; then
            echo "ok: nixosConfigurations.${name}"
        else
            echo "FAILED: nixosConfigurations.${name}"
            nix eval --raw --no-warn-dirty --max-jobs 0 "${attr}" 2>&1 | tail -20
            FAILED=1
        fi
    done
}

# Sections are independent and mostly wait on a nix eval or the daemon, so
# they run concurrently (the runner has 16 vCPU) instead of back to back —
# sequentially they summed to ~6 min. Each writes to its own log, which is
# printed whole as soon as that section finishes, so a hung section cannot
# hide the others' output when the job times out.
#
# nix eval runs client-side inside the runner pod, so concurrent sections add
# up against its memory limit (16Gi in home-cluster; all sections together
# peaked at ~8GiB). Re-check that before adding more concurrent evals.
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${LOG_DIR}"' EXIT
SECTIONS=()
PIDS=()

# Job control gives every background section its own process group, so
# cancelling can signal the nix clients under it, not just the subshell.
set -m
cancel_sections() {
    local pid
    for pid in "${PIDS[@]}"; do
        kill -TERM -- "-${pid}" 2>/dev/null || true
    done
    exit 143
}
trap cancel_sections TERM INT

# run_section <name> <function> — run <function> in the background. N.rc
# appears once it is done and holds 0 or 1 (1 when it set FAILED or returned
# non-zero).
run_section() {
    local name="$1" fn="$2"
    SECTIONS+=("${name}")
    local n="${#SECTIONS[@]}"
    (
        FAILED=0
        "${fn}" || FAILED=1
        echo "${FAILED}" >"${LOG_DIR}/${n}.rc.tmp"
        mv "${LOG_DIR}/${n}.rc.tmp" "${LOG_DIR}/${n}.rc"
    ) >"${LOG_DIR}/${n}.log" 2>&1 &
    PIDS+=("$!")
}

section_modules() {
    check_module_set ".#nixosModules"
    check_module_set ".#homeModules"
    check_module_set ".#overlays"
    check_drv_set ".#devShells.${TARGET_SYSTEM}"
}

section_packages() {
    check_drv_set ".#packages.${TARGET_SYSTEM}"
    build_changed_packages ".#packages.${TARGET_SYSTEM}"
}

# build_check <name> — build checks.<system>.<name>, fail the section if it fails.
build_check() {
    nix build --no-link --no-warn-dirty ".#checks.${TARGET_SYSTEM}.$1" || {
        echo "FAILED: checks.${TARGET_SYSTEM}.$1"
        FAILED=1
    }
}

section_copilot_bats() { build_check copilot-cli-bats; }
section_delegation_bats() { build_check delegation-bats; }
section_hetzner_bats() { build_check hetzner-volume-verify-bats; }
section_pr_check_bats() { build_check pr-check-bats; }

section_scripts() {
    .github/scripts/check-forgecdn-paths.sh || FAILED=1
    nix shell --no-warn-dirty --inputs-from . nixpkgs#yq-go \
        --command .github/scripts/check-skill-frontmatter.sh || FAILED=1
}

section_aarch64_hosts() { check_hosts_for_system "aarch64-linux"; }

run_section "nixosModules, homeModules, overlays, devShells.${TARGET_SYSTEM}" section_modules
run_section "packages.${TARGET_SYSTEM} (evaluated; changed ones built)" section_packages
run_section "copilot-cli script tests (bats)" section_copilot_bats
run_section "delegation script tests (bats)" section_delegation_bats
run_section "hetzner-volume-verify script tests (bats)" section_hetzner_bats
run_section "pr-check script tests (bats)" section_pr_check_bats
run_section "CurseForge CDN paths, skill frontmatter" section_scripts
run_section "aarch64-linux nixosConfigurations (evaluated)" section_aarch64_hosts

PENDING="${#SECTIONS[@]}"
PRINTED=" "
while [ "${PENDING}" -gt 0 ]; do
    for n in $(seq 1 "${#SECTIONS[@]}"); do
        case "${PRINTED}" in *" ${n} "*) continue ;; esac
        # A section that died before writing its .rc (disk full, killed) would
        # otherwise be waited on until the job timeout.
        if [ ! -f "${LOG_DIR}/${n}.rc" ]; then
            kill -0 "${PIDS[$((n - 1))]}" 2>/dev/null && continue
            [ -f "${LOG_DIR}/${n}.rc" ] || echo 1 >"${LOG_DIR}/${n}.rc" 2>/dev/null || true
        fi
        if [ "$(cat "${LOG_DIR}/${n}.rc" 2>/dev/null || echo 1)" = 0 ]; then
            status=ok
        else
            status=FAILED
            FAILED=1
        fi
        echo "== ${SECTIONS[$((n - 1))]}: ${status} =="
        cat "${LOG_DIR}/${n}.log"
        PRINTED="${PRINTED}${n} "
        PENDING=$((PENDING - 1))
    done
    sleep 1
done
wait

exit "$FAILED"
