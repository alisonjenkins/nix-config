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

### Root cause (instrumented parasite, `instrument-parasite.py`)

Per-iov instrumentation (splice one iov at a time, log the first failure)
pinpoints it:

```
SPLICE-DBG fail iov #0 base=0x771da1edf000 len=0x1000 ret=-14   (EFAULT)
```

The faulting page lives in a cluster of **private file-backed mappings**
(`reg fp`, `flags 0x2` = MAP_PRIVATE, shmid 0x7, non-zero file offsets) —
a mmap'd file (shared lib / jar / jimage), not anon heap. criu's parasite
tries to `vmsplice` a page of a private *file* mapping that is **not
resident** at splice time → EFAULT. Standalone C proves `vmsplice` works
on resident pages, so criu's pagemap/soft-dirty interpretation for private
file mappings disagrees with what this kernel reports (it tries to dump a
clean/evicted file page). This is a criu↔kernel pagemap-semantics issue,
not a userspace-tweakable one — patching it means changing criu's
file-mapping dump-set selection, which may itself depend on the kernel's
pagemap behaviour.

### The exact cachyos cause + what's ruled out

Kernel from `xddxdd/nix-cachyos-kernel` -> `CachyOS/linux-cachyos`
(`1c61dfd`) + `CachyOS/kernel-patches` (`579b7bd`). Two cachyos mm changes
explain it:

- **`VM_READAHEAD_PAGES` 128 KB -> 8 MB** (`0001-cachyos-base-all.patch`,
  `include/linux/pagemap.h`). mmap'd files (the JDK's `lib/modules`
  jimage, jars, .so) get up to 2048 pages of speculative readahead +
  fault-around. Those pages show present in `/proc/pid/pagemap` but aren't
  cleanly splice-able, so the parasite `vmsplice` returns EFAULT or a
  partial count on them.
- **`CONFIG_READ_ONLY_THP_FOR_FS=y`** — read-only file mappings can be
  collapsed to huge folios; criu 3.17.1 mis-handles a sub-page of a file
  huge-folio -> EFAULT. Turning THP off flips that EFAULT into the partial
  splice, confirming both are in play.

Instrumented criu (`PIPE-DBG`) proved the **page-pipe is NOT the problem**
(forced to 64 MiB; most VMA batches splice fully — pages-1.img reaches
~24 MB). The workingset-protection sysctls one theory flagged
(`vm.clean_min_ratio` etc.) **do not exist** in this kernel build — ruled
out. System mitigations (THP off, per-device `read_ahead_kb=0`,
`drop_caches`) reduce but do NOT eliminate the stray unfaulted page.

## Conclusion / next steps

The clean fix is to ensure every mapped page has a real PTE before the
checkpoint — which the **lifecycle coremod** does naturally: before
`Core.checkpointRestore()` it can `madvise(MADV_POPULATE_READ)` /
`MADV_RANDOM` or just touch all mapped ranges, leaving no
present-but-unfaulted file pages for criu to trip on. So this cachyos
blocker is plausibly **dissolved by the coremod step we need anyway** —
verify once the coremod exists. Alternatives:
1. **Coremod fault-in step** (preferred) — fold MADV_POPULATE_READ into the
   warm phase; retest checkpoint on cachyos.
2. **Stock kernel (aarch64/AWS)** — readahead 128 KB, issue doesn't arise;
   the production target anyway.
3. **criu `generate_iovs`/`mem.c` surgery** — drop non-resident file pages
   from the dump set. Deepest, last resort.

Coremod (warm -> unload-world -> checkpoint; restore -> load live world) is
NOT started — gated on a working checkpoint primitive, but the root cause
above means it should be attempted WITH the fault-in step on cachyos.
