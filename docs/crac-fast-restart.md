# CRaC fast-restart for the Arkana server — investigation log

Goal: checkpoint a warmed JVM (mods + registries + JIT) and restore it in
ms instead of the 5-8 min Minecraft cold boot, so a spot-interrupted k3s
master recovers near-instantly. See the terraform repo's plan for context.

Branch: `experiment/crac-server-fast-restart`.

## What works (committed, reusable)

- **`liberica-jdk-crac`** (`pkgs/liberica-jdk-crac`) — BellSoft Liberica JDK
  21 with CRaC, x86_64. Builds, runs, CRaC flags present
  (`-XX:CRaCCheckpointTo` / `CRaCRestoreFrom`), bundled `criu 3.17.1-crac`
  + `criuengine`. `nix build .#liberica-jdk-crac`.
- **`crac-criu`** (`pkgs/crac-criu`) — CRaC's criu fork (release-1.5.2)
  built by overriding nixpkgs criu. Build fixes: vendored lz4 fetched
  separately (fetchSubmodules trips the fetchgit cleanup bug), drop the
  Makefile git-submodule step, dynamic-link protobuf-c/libnet/libnl-3,
  patch crit off distutils.
  - **vDSO probe fix** — `COMPAT_VDSO_BUF_SZ` 4→16 pages. The bundled and
    fork criu (both 3.17.1-based) otherwise abort kerndat init on recent
    kernels with "Compatible vdso's size is bigger than reserved buf".
    This is a genuine, reusable fix for any recent kernel.
- GUI askpass: `~/.local/bin/gui-askpass.sh` (zenity) → `SUDO_ASKPASS=... sudo -A`.
- Smoke harness: `/tmp/crac-test/` (`Counter.java`, `run.sh`,
  `vmsplice_test.c` / `vmsplice_multi.c` / `vmsplice_rdend.c`).

## The wall: criu parasite page-dump on `7.0.1-cachyos-lto`

Checkpoint reaches the page-dump and fails there. Symptoms, all on this
kernel:

| criu | flags | result |
|---|---|---|
| bundled 3.17.1 | — | kerndat vDSO probe abort (fixed by the buffer patch) |
| crac 3.17.1 + vDSO fix | GIFT | `vmsplice` EFAULT (`-14`) — GIFT needs exclusively-owned anon pages |
| crac 3.17.1 + vDSO fix | no-GIFT | partial splice (stops on the untouched-heap zero-page) |
| crac 3.17.1 + vDSO fix | no-GIFT + AlwaysPreTouch | EFAULT again on real pages |
| vanilla criu 4.1.1 | (engine default) | EAGAIN / partial splice |
| any of the above | parasite forces `F_SETPIPE_SZ` | no change |

### The kernel itself is healthy

Standalone C (`vmsplice_*.c`) proves `vmsplice` works fully on this
kernel for every pattern criu uses:
- 1024 contiguous pages, GIFT|NONBLOCK → FULL
- 1024 scattered 1-page iovs, NONBLOCK → FULL
- resize via read-end fd, splice via write-end → FULL
- `F_SETPIPE_SZ` reaches 8 MB

So it is **not** the kernel's vmsplice/pipe, **not** pipe sizing, **not**
GIFT, **not** zero-pages. The failure is specific to criu's
**ptrace-injected parasite** doing the dump from inside the seized JVM on
this custom (cachyos-lto, LTO + mm/sched patches) kernel — a context that
does not reproduce in standalone C.

## Conclusion / next steps

The fixable-in-criu-userspace levers are exhausted. Remaining options:
1. **Stock-kernel validation (decisive, cheap):** run the same harness in
   a NixOS qemu VM on the default kernel. If it passes, cachyos-lto is
   confirmed the cause and we have a working, repeatable baseline +
   CI test for the coremod work. If it fails too, isolates to our setup.
2. **aarch64/AWS:** build aarch64 `liberica-jdk-crac` and validate on an
   EC2/k3s node (stock kernel = production target).
3. **Deep parasite debugging:** instrument criu/compel's parasite to trace
   the exact failing address/page on cachyos-lto. Days, uncertain, and
   likely a kernel-patch interaction rather than a criu bug.

Coremod (warm → unload-world → checkpoint; restore → load live world) is
NOT started — it's gated on a working checkpoint primitive first.
