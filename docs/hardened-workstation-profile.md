# Hardened managed-workstation profile: gap analysis

Status: draft, 2026-10-29. Nothing here is implemented yet.

## Goal

Opt-in NixOS modules for a locked-down, directory-joined workstation:
directory login, endpoint protection, encrypted disks, kernel and SSH hardening,
and a restricted app store. Each control below comes from public guidance
(upstream project docs, kernel documentation, systemd and OpenSSH manuals, CIS-style
baselines). The modules stay generic: no tenant, domain, group or key material
in the repo. Those come from sops secrets or per-host options.

## Summary

| # | Control | Here today | Work |
|---|---|---|---|
| 1 | Entra ID login (Himmelblau) | none | new module |
| 2 | Login allow-list | none | option on #1 |
| 3 | Endpoint protection agent | none | interface-only module |
| 4 | Disk encryption bound to TPM | LUKS + PCR 15 (`modules/luksPCR15`) | configurable PCRs, recovery key |
| 5 | Secure Boot | lanzaboote (`modules/base`) | covered |
| 6 | Kernel lockdown | none | new option |
| 7 | Kernel memory hardening | none | new option |
| 8 | IOMMU isolation | `amd_iommu=off` on `ali-work-laptop` | new option, host conflict |
| 9 | SSH hardening | key-only, no root | extend |
| 10 | PAM review | NixOS default | review |
| 11 | Mandatory access control | none | AppArmor |
| 12 | Flatpak restrictions | `nix-flatpak`, open remotes | new module |
| 13 | Service exposure | per host | audit |
| 14 | Break-glass local admin | normal user + sudo | sops hashed password option |

## Per-control notes

### 1-2. Himmelblau (Entra ID login)

Upstream (`himmelblau-idm/himmelblau`) ships a flake with `nixosModules.himmelblau`.
It is not in nixpkgs. Plan:

- Add it as a flake input and register it in `pins/registry.json` (see the `pins` skill).
- Wrap it in `modules/managed-workstation/himmelblau.nix` with options `domain`,
  `hsmType` (default `tpm`), `applyPolicy`, `allowGroups`, `localGroups` and
  offline-login TTL.
- Use the upstream PAM and NSS integration; NixOS generates PAM from
  `security.pam.services`, so do not hand-edit `/etc/pam.d`.
- Assert a TPM 2.0 is enabled when `hsmType = "tpm"`.
- Add a `nixosTest` with a software TPM that checks the daemon starts and that
  `getent passwd` does not hang when it stops.

### 3. Endpoint protection

No nixpkgs package exists for the vendor agent. Ship an interface-only module
(`enable`, `onboardingFile` from sops) and leave the package to whoever holds a
licence. Do not commit vendor packages or onboarding files.

### 4. Disk encryption

Add `modules.luksPCR15.pcrs` (default `[ 15 ]`) so a host may bind to `[ 7 ]` or
`[ 7 15 ]`. PCR 7 tracks Secure Boot policy and survives kernel updates. Also add
recovery-key enrolment (`systemd-cryptenroll --recovery-key`) with the output
encrypted to a configurable public key.

### 6-8. Kernel arguments

New `modules.hardenedKernel`, one boolean per group, all off by default:

| Option | Params |
|---|---|
| `lockdown` | `lockdown=integrity` |
| `memoryZeroing` | `init_on_alloc=1 init_on_free=1` |
| `kstackRandomize` | `randomize_kstack_offset=on` |
| `noVsyscall` | `vsyscall=none` |
| `pageShuffle` | `page_alloc.shuffle=1` |
| `noSysrq` | `sysrq_always_enabled=0`, `kernel.sysrq = 0` |
| `iommuIsolation` | `iommu=force amd_iommu=force_isolation intel_iommu=on` |

Conflicts on `ali-work-laptop`:

- `amd_iommu=off` is set; both cannot apply. Measure `force_isolation` first,
  since the GPU uses a large TTM window.
- `lockdown=integrity` blocks hibernation, which this host uses.
- Lockdown rejects unsigned out-of-tree modules; NixOS does not sign them by default.

### 9. SSH

Add `AllowGroups`, `MaxAuthTries = 3`, `LoginGraceTime = 30`,
`GSSAPIAuthentication = no`, and restrict key exchange, ciphers and MACs to
curve25519, chacha20-poly1305, AES-GCM and ETM MACs (per the OpenSSH manual
and Mozilla's modern guidelines).

### 11. Mandatory access control

NixOS has no supported SELinux. Use `security.apparmor` with stock profiles,
then confine the high-value daemons. Follow-up work.

### 12. Flatpak restrictions

`modules.flatpakLockdown`:

- polkit rule denying `org.freedesktop.Flatpak.{remote-add,remote-modify,remote-delete,override,configure}`
  for non-wheel users;
- a remote filter generated from `services.flatpak.packages`;
- immutable per-user flatpak `repo`, `app` and `overrides` directories, set by a
  tmpfiles-driven oneshot rather than PAM exec.

### 14. Break-glass admin

`users.breakglass.hashedPasswordFile` read from sops, excluded from directory
login and from SSH `AllowGroups` unless a key is set.

## Module layout

```
modules/managed-workstation/
  default.nix        # modules.managedWorkstation.enable
  himmelblau.nix
  endpoint-agent.nix
  kernel-hardening.nix
  ssh.nix
  flatpak-lockdown.nix
  breakglass.nix
```

## Order of work

Each item is one atomic commit that builds on its own.

1. `kernel-hardening.nix`, all options off.
2. SSH tightening.
3. `luksPCR15.pcrs` and recovery-key enrolment.
4. Flatpak lockdown.
5. Himmelblau input, pin entry, module, test.
6. Break-glass option.
7. AppArmor baseline.
8. Endpoint-agent interface.

## Open questions

- First consumer: `dev-vm` or a VM host, because `ali-work-laptop` has the IOMMU and hibernate conflicts.
- Can Himmelblau be tested without a tenant? Check the upstream tests for a mock.
