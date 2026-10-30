# 0057. Manage kernel options through composable `modules.kernelTuning` profiles

- Status: Proposed
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

**Profiles are named sets of knob names.** `modules.kernelTuning.profiles` is
a list of profile names. Each selected profile sets `knob = mkDefault true`
for its members. Profiles only ever switch knobs on, so two profiles never
produce conflicting definitions and compose freely. A host switches off one
knob with a plain `modules.kernelTuning.<knob> = false`, which beats
`mkDefault` without `mkForce`.

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
- Collisions: a check over the final `boot.kernelParams` and
  `boot.kernel.sysctl` flags a key that two sources define with different
  values, including settings made outside this module.
- A knob whose minimum kernel version is above the host's kernel warns and is
  skipped.

**Scope of the first change.** The module, table, profiles and their checks.
No host is migrated in that change.

**Migration is later and provable.** Existing settings move into the module
one group at a time, one atomic commit each. A migration commit must be a
no-op for the host: the sorted `nix eval --json` of `boot.kernelParams` and
`boot.kernel.sysctl` is identical before and after. Hardware workarounds
(`amd_iommu=off` on `ali-work-laptop`, GPU quirks) stay in the host's own
configuration and are never a profile default.

**Candidate knobs are verified first.** A knob enters the table only with a
public source and a check against the kernel the fleet ships (is it already
the default? does it exist on that version?). Research for this record is
public-source only.

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
| `/dev/mem`, `/dev/kmem`, `/dev/kcore`, `/dev/ioports` | none; check strict devmem in the shipped kernel's config |
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
with `CONFIG_MODULE_SIG`; NixOS kernels are not, but we can build ours that
way (`boot.kernelPatches` with `structuredExtraConfig`, or an override of the
CachyOS input, which means a long LTO build per bump). An ephemeral build-time
key signs only the in-tree modules, so any host with an out-of-tree module
(NVIDIA, evdi, ZFS) cannot enforce signatures. A persistent key cannot be a
build input, because the store is world-readable; it needs a signing step
outside the build that feeds the binary cache. That is its own infrastructure
and gets its own ADR. Until then the knob table may carry a `moduleSigEnforce`
entry, off in every profile, which asserts the kernel was built with
`MODULE_SIG` and warns about unsigned out-of-tree modules. It is not part of
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
- A host's intent reads as `profiles = [ "hardened-server" "server-throughput" ]`
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
