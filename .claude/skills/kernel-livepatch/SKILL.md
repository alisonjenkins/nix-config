---
name: kernel-livepatch
description: How to write, build and prove a hand-written kernel livepatch module for a NixOS node built with CONFIG_LIVEPATCH (the Hetzner nodes). Use when a kernel CVE or bug needs fixing without a reboot, when asked about live kernel patching, klp_patch, kpatch, or `scripts/livepatch`, or when `patch-node.sh` reports the kernel changed and a reboot is the only path.
paths:
  - "scripts/livepatch/**"
  - "flake-modules/livepatch-tests.nix"
  - "modules/hetzner/default.nix"
---

# Kernel livepatch

A livepatch replaces one kernel function at runtime. It fits a small fix inside
a function that is traced by ftrace. It does not fit a data-structure change, an
inlined function, or anything needing a symbol the kernel does not export.

## Scope

- x86_64 only: mainline arm64 has no `HAVE_LIVEPATCH`. The Hetzner module sets
  `CONFIG_LIVEPATCH=y` only there.
- A module is built for one exact kernel build (vermagic). A new kernel build
  needs a new module, or a reboot.
- A loaded patch taints the kernel (`TAINT_LIVEPATCH`). That is expected.
- `.replace = true` makes each module cumulative: it replaces all earlier
  patches, so a later module must carry every fix still wanted.
- The in-tree `klp-build` exists only from 6.19; the pinned kernel is 6.18.x.
  nixpkgs has no kpatch. Without klp relocations a module can call only
  exported symbols.

## Workflow

1. Get the kernel dev output of the exact running kernel:
   `nix build .#nixosConfigurations.hetzner-karpenter-node-amd64.config.boot.kernelPackages.kernel.dev --print-out-paths --no-link`
2. Scaffold: `scripts/livepatch/new-module.sh --name lp_x --target func --ret int --args 'struct foo *f' --cve CVE-... --out lp_x.c`
   (`--object MODULE` when the function is in a loadable module, not vmlinux).
3. Replace each `LIVEPATCH-TODO`: copy the original function from the exact
   kernel source (the tarball in the kernel derivation) and apply the fix.
4. Build: `scripts/livepatch/build-module.sh --kernel-dev <dev> --src lp_x.c --out out/`
   - exit 2: marker left. exit 3: needs unexported symbols (names printed).
     exit 4: compile failure.
   - exit 3 is final for a hand-written module. Rewrite the fix without the
     symbol, or use kpatch, or reboot.
5. Prove on a twin, never first on the master:
   `scripts/livepatch/verify-on-host.sh --host ali@<twin> --ko out/lp_x.ko --check 'cmd' --expect REGEX`
   The check must not match before loading and must match after. The script
   then disables and unloads the patch and requires the old behaviour and the
   same `boot_id` (exit 3 load/transition, 4 no change, 5 no revert, 6 reboot).
6. Applying to the master is a live-infrastructure change: ask the user first,
   take a fresh snapshot, and keep the `patch-node.sh` reboot path as fallback.

## Canonical refusal

`version_proc_show` prints `linux_proc_banner`, which is not exported. A first
draft using it was refused with exit 3; the working module formats
`utsname()->sysname/release/version` itself and adds a marker line. Reproduced
on the twin: `/proc/version` gained `livepatched: lp_version_fix`, reverted on
unload, `boot_id` unchanged.

## Disabling by hand

```
echo 0 > /sys/kernel/livepatch/<name>/enabled   # wait for transition == 0
rmmod <name>
```

A module must be disabled before `rmmod`.
