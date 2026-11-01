# 0057. Manage kernel options through composable `modules.kernelTuning` profiles

- Status: Accepted
- Date: 2026-10-29

## Context

Kernel parameters, sysctls and module blacklists are set in about 25 files:
`modules/base`, `modules/desktop`, `modules/power-management`,
`modules/vfio-isolate`, `modules/podman`, `modules/luksPCR15` and most host
directories under `flake-modules/hosts/`. Nothing records which setting is
security, performance, gaming or a hardware workaround, so a host cannot be
audited or reproduced from its intent. [0056](0056-tune-vm-sysctls-for-zram-in-base.md)
shows the cost: the same swap sysctls had drifted into per-host copies.

A managed-workstation hardening effort needs a set of opt-in hardening knobs
(`lockdown`, `init_on_alloc`, `slab_nomerge`, ...). Those knobs are not
workstation-specific: servers want most of them, and performance and gaming
tuning has the same shape (a named setting, a cost, something it breaks). Three
requirements follow:

1. One place to read and change every kernel option a machine uses.
2. Bundles for a kind of machine (laptop, server, gaming desktop) that can be
   combined, such as `hardened-workstation` with `gaming`.
3. Any single setting of a bundle can be switched off on a host whose hardware
   or workload does not tolerate it.

## Decision

Add `modules/kernel-tuning/`, exported as `self.nixosModules.kernel-tuning`,
with options under `modules.kernelTuning`.

**One static knob table.** Each knob is an entry with: category (`security`,
`performance`, `gaming`, `hardware`), the params, sysctls and blacklisted
modules it contributes, the minimum kernel version, a cost (`none`, `low`,
`medium`, `high`), a one-line "breaks" note, and `conflictsWith`. The table is
plain data and never reads `config`. A boolean option per knob is generated
from it, default `false` unless a profile enables it. Adding a knob is adding
a table entry.

A knob may also set `sysctlPriority` (default 100, the plain priority). It
exists for settings that `modules/base` used to set with `mkDefault` (1000):
the emitter wraps their values in `mkOverride` at that priority, so a host's
`mkOverride` or `mkForce` still wins, as it did before the setting moved into
the table. A knob left at 100 collides with a differing plain host value.

**Profiles are named sets of knob names.** `modules.kernelTuning.profiles` is
a list of profile names. Each selected profile sets `knob = mkDefault true`
for its members. Profiles only ever switch knobs on, so two profiles never
produce conflicting definitions and compose freely. A host switches off one
knob with a plain `modules.kernelTuning.<knob> = false`, which beats
`mkDefault` without `mkForce`.

The shipped profiles:

| Profile | Knobs | Selected by |
|---|---|---|
| `hardened-workstation` | `kstackRandomize`, `initOnAlloc`, `noVsyscall`, `pageShuffle`, `slabNomerge`, `debugfsOff`, `kexecDisable` | `modules.desktop` |
| `hardened-server` | the same set | each server host |
| `desktop` | `schedAutogroup`, `watermarkBoostOff`, `watermarkScaleBalanced`, `thpMadvise` | `modules.desktop` |
| `gaming` | `splitLockMitigateOff`, `compactionProactivenessOff`, `maxMapCountHigh`, `cfsBandwidthSliceShort` | `ali-desktop`, `ali-framework-laptop`, `ali-steam-deck` |

`desktop` holds the responsiveness tuning any interactive machine wants;
`gaming` holds the settings that trade safety margin or latency for throughput
in games. A host that does not want one knob of a profile sets it to `false`
(`ali-mba-linux` does this for `schedAutogroup` and `thpMadvise`).

**Value-typed settings stay out of profiles.** `lockdown` (an enum) and
numeric settings such as a panic timeout are explicit options that a host
sets. A profile may only set a value-typed option if exactly one profile
owns it.

**Laptop profiles never include `lockdown`.** Lockdown disables hibernation,
and laptops need it: a suspended machine must hibernate before the battery
runs flat, and low battery must trigger hibernation. Hibernating hosts take
the individual restrictions lockdown bundles as separate knobs (`kexec` off,
`debugfs=off`, MSR writes off) and keep the image on LUKS swap. LUKS protects
the image's confidentiality. It does not authenticate it, so an offline
attacker could in principle replay or corrupt the image; a TPM-bound key and
Secure Boot narrow that, and the residual risk is accepted for laptops.
Lockdown itself is an explicit per-host option for machines that never
hibernate.

**Emitters read knobs only.** A single emitter turns enabled knobs into
`boot.kernelParams`, `boot.kernel.sysctl` and `boot.blacklistedKernelModules`.
It never reads which profile enabled a knob.

**Conflicts assert; nothing is resolved silently.**

- Declared conflicts: if two enabled knobs list each other in
  `conflictsWith` (for example `mitigations=off` from a performance knob
  against any hardening knob), evaluation fails with both knob names.
- Environment conflicts: `lockdown` set together with `boot.resumeDevice`
  asserts; set together with `boot.extraModulePackages` warns, because NixOS
  does not sign out-of-tree modules.
- Collisions: a check over the final `boot.kernelParams` flags a key that
  the module emits when another source defines it with a different value.
  Duplicates between two other modules are left alone: the kernel takes the
  last value, and `ali-framework-laptop` carries one from nixos-hardware
  (`amdgpu.dcdebugmask`). Sysctls need no check, since NixOS fails evaluation
  on conflicting definitions itself.
- A knob whose minimum kernel version is above the host's kernel warns and is
  skipped.

**Scope of the first change.** The module, table, profiles and their checks.
No host was migrated in that change. Hosts and `modules.desktop` select
profiles in later commits, and `modules/base` imports the module so every host
can.

**Migration is later and provable.** Existing settings move into the module
one group at a time, one atomic commit each. A migration commit must be a
no-op for the host: the sorted `nix eval --json` of `boot.kernelParams` and
`boot.kernel.sysctl` is identical before and after. Hardware workarounds
(`amd_iommu=off` on `ali-work-laptop`, GPU quirks) stay in the host's own
configuration and are never a profile default. The generic sysctls that
`modules/base` used to set (vm, net, tcp, icmp, hpet, dentry) now live in the
table and base enables them with `mkDefault`.

**Candidate knobs are verified first.** A knob enters the table only with a
public source and a check against the kernel the fleet ships (is it already
the default? does it exist on that version?). Research for this record is
public-source only.

## Where a knob is applied: command line, sysctl, sysfs or modprobe

A knob lives in one table and carries one field per target it needs: `params`,
`sysctls`, `sysfs`, `modprobe`. Each target has its own emitter file under
`modules/kernel-tuning/` that reads only the enabled knobs, so a target can
grow without touching the others. The rule for choosing a target:

| Use | When | Examples |
|---|---|---|
| Kernel command line (`params`) | The setting must hold before any userspace runs, has no runtime form, or configures a built-in driver or subsystem. Sysctls apply only after the initrd, a window of several seconds. | `init_on_alloc`, `init_on_free`, `slab_nomerge`, `page_alloc.shuffle`, `vsyscall=none`, `debugfs=off`, `mitigations=`, `nosmt`, `iommu=`, `amd_iommu=`, `lockdown=` |
| sysctl (`sysctls`) | The setting is runtime-tunable, reversible or host-specific, and applying it a few seconds into boot is early enough. Includes one-way switches that should apply after boot work finishes. | `vm.swappiness`, `vm.max_map_count`, `kernel.split_lock_mitigate`, `vm.compaction_proactiveness`, `net.core.*`, `kernel.sysrq`, `kernel.kexec_load_disabled` |
| sysfs (`sysfs`) | There is no sysctl and no boot parameter, only a file under `/sys`. Applied through systemd-tmpfiles or udev. | transparent hugepage mode, I/O scheduler, cpufreq boost |
| modprobe options (`modprobe`) | The setting is a parameter of a driver built as a module, so the command line form does not apply. | `msr.allow_writes` when `msr` is a module (name unverified) |

When a setting has both a command-line and a runtime form (for example
`transparent_hugepage`), prefer the runtime form unless the setting must hold
before userspace starts, and record the choice beside the knob.

Why the split matters beyond tidiness:

- NixOS already fails evaluation when two modules set one sysctl to different
  values at equal priority. `boot.kernelParams` is a plain list with no such
  check, so the collision assertion above exists for params only.
- Several sysctls are set in many places today (`net.core.rmem_max` in seven
  files, diverging `vm.swappiness` values). Shared sysctl knobs, such as one
  for large network buffers, are how those duplicates go away when hosts
  migrate.
- Whether `randomize_kstack_offset` has a runtime form on the shipped kernels
  is unverified; confirm it per knob before choosing its target.

## Lockdown coverage on hibernating hosts

Mainline refuses hibernation while lockdown is active
(`hibernation_available()` checks `LOCKDOWN_HIBERNATION`; the source has no
exemption for encrypted images), so a hibernating host runs without it. What
`kernel_lockdown(7)` restricts, and what replaces it:

| Lockdown restriction | Replacement knob |
|---|---|
| kexec of unsigned binaries | `kernel.kexec_load_disabled=1`, stricter than lockdown |
| debugfs | `debugfs=off` |
| Unsigned modules | `module.sig_enforce=1`, deferred below |
| x86 MSR writes | `msr.allow_writes=off` (name from memory, unverified) |
| `/dev/mem`, `/dev/kmem`, `/dev/kcore`, `/dev/ioports` | none needed for `/dev/mem` and `/dev/ioports`: `CONFIG_STRICT_DEVMEM` and `CONFIG_IO_STRICT_DEVMEM` are on in nixpkgs kernels (`common-config.nix`) and in the running CachyOS 7.3 config; `/dev/kmem` and `/dev/kcore` unchecked |
| `ioperm`/`iopl`, PCI BAR access, KD*IO ioctls, `TIOCSSERIAL` | none; lost |
| ACPI table override, custom methods, error injection, RDSP address | none; lost |
| BPF and kprobes restrictions | none; lost |
| Module parameters that set hardware parameters | none; lost |

The rows marked lost are the price of hibernation. Sources: `kernel_lockdown(7)`
(man-pages 6.19) and `kernel/power/hibernate.c` at mainline master, read
2026-10-30. A distribution kernel such as CachyOS may patch the hibernation
check, so confirm on the shipped kernel before relying on this.

## Deferred

**Module signature enforcement.** `module.sig_enforce=1` needs a kernel built
with `CONFIG_MODULE_SIG`. Both kernels we ship have it: nixpkgs'
`common-config.nix` sets `MODULE_SIG = yes` with an empty `MODULE_SIG_KEY`
(it signs each module with a deterministic per-module certificate from
kmodigest instead of an ephemeral build key), and the running CachyOS 7.3
config has `CONFIG_MODULE_SIG=y`, `MODULE_SIG_FORCE` unset. What is unknown
is whether enforcement would accept our out-of-tree modules (NVIDIA, evdi,
ZFS) and how the CachyOS input signs its modules; a persistent key cannot be
a build input, because the store is world-readable. Enforcement is therefore
a separate piece of work with its own ADR. Until then the knob table may carry
a `moduleSigEnforce` entry, off in every profile, which asserts the kernel was
built with `MODULE_SIG` and warns about out-of-tree modules. It is not part of
the first change.

## Alternatives rejected

- **Keep the knobs under `modules.managedWorkstation.kernel`.** Servers and
  the gaming desktop need the same mechanism; a workstation namespace would
  make every other consumer import a workstation module.
- **A hardening-only module.** Performance and gaming settings conflict with
  hardening (`mitigations=off`, THP, split-lock handling). The conflict
  checks need both in one table to see each other.
- **Profiles as full option bundles with their own values.** Two profiles
  could then set the same option to different values, and the module system
  picks one by priority. The knob-set shape makes that impossible.
- **Profiles that win over host settings (`mkForce`).** A profile is a
  default; the host knows its hardware.
- **Migrate every host in one change.** It cannot be reviewed or reverted per
  host, against the atomic-commit rule.
- **Use nixpkgs `profiles/hardened.nix`.** The profile is gone: at the pinned
  nixpkgs it is a `mkRemovedOptionModule` stub (removed for 26.05 because its
  bundle hurt stability, features and performance). Its old contents were a
  fixed set that disabled user namespaces and unprivileged BPF, which desktops
  and k8s hosts need. Individual knobs from the pre-removal file may still
  enter the table on their own merits.

## Consequences

- Every kernel option the module owns has a category, a cost and a recorded
  break condition, and appears in one table.
- A host's intent reads as `profiles = [ "hardened-workstation" "gaming" ]`
  plus a short list of per-knob exceptions.
- Until hosts are migrated, settings exist in both places; the collision check
  is what keeps that safe, and it will fire on any pre-existing disagreement.
- The table needs upkeep as kernels change defaults. The minimum-version field
  and the per-kernel check limit the damage; a knob that became a default is
  removed from the table.
- The `kernel-hardening` module drafted during the managed-workstation work is
  folded in as the first set of `security` knobs and is not shipped under that
  name.

## Evidence

None yet for the knob values. The inventory of existing settings and the
public-source candidate lists are being collected; the first change records
them and the kernel versions checked.

## Revisit when

A profile needs to turn a knob off (the "profiles only enable" rule is wrong),
the collision check is noisy enough that hosts silence it, or the table grows
past what one file can hold readably.
