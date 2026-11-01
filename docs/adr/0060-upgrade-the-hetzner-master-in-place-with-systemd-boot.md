# 0060. Upgrade the Hetzner master in place with systemd-boot, and defer the edge node

- Status: Accepted
- Date: 2026-10-31

## Context

[0021](0021-patch-hetzner-master-in-place.md) chose two things. It patches the Hetzner
master in place, and it moves the call stack to a separate `edge` node so a master reboot
does not drop a call. It also planned NixOS GRUB on BIOS for the boot path.

Checks on 2026-10-31 change the boot path and the edge plan:

- The master, `hetzner-k8s-master-1`, is a `cpx32` that boots UEFI with systemd-boot 260.x.
  The image's EFI system partition holds one static unified kernel image, `EFI/Linux/nixos.efi`,
  which names one fixed generation. A reboot never applied a deploy.
- Commit `c2084352` enables NixOS-managed systemd-boot. The boot menu then follows the
  system profile again.
- The image's Nix database was empty. `/nix/store` was populated, but the database listed
  zero paths, so the first in-place deploy cannot run until the store is registered.
- The household runs with a limited number of machines. A second server is not created now.

## Decision

1. **Patch the master in place with NixOS-managed systemd-boot.** The boot path is UEFI
   systemd-boot, not GRUB on BIOS. The GRUB plan in spec 003 is dropped.
2. **Defer the edge node.** The call-survival goal of 0021 is deferred, not dropped. A master
   reboot takes calls and chat down for a few minutes. The state volume is LUKS, so each boot
   needs the owner's passphrase, and every reboot is attended.
3. **Script the fall-back.** The patch flow is:
   - Install the new generation. The default stays on the old generation.
   - Set the new entry as a one-shot with `bootctl set-oneshot`, then reboot.
   - Run the health check, `k3s kubectl get --raw=/readyz`.
   - If it passes, run `bootctl set-default` on the new entry.
   - If it fails or hangs, hard reset the server through the Hetzner API. The boot falls back
     to the default, which is the old generation. A hard reset took about 20 seconds in the rehearsal.

   The pinned nixpkgs systemd-boot has no boot counting, so nothing falls back on its own.
4. **Register the store before the first in-place deploy.** A one-off scan on the live master
   writes the registration for the existing store paths. Future images bake the same
   registration in with `closureInfo`.
5. **Set the default explicitly on every patch.** `bootctl set-default` writes an EFI
   variable. That variable overrides `default` in `loader.conf`, so a change to `loader.conf`
   alone changes nothing once the variable is set.

The steps are in [the runbook](../hetzner-inplace-upgrade-runbook.md).

## Alternatives rejected

- **GRUB on BIOS with `grub-reboot`** (spec 003 plan). The master boots UEFI. The image
  already ships systemd-boot on the ESP, and NixOS manages it.
- **Edge node now.** It costs a server and a capacity check, and the machine limit rules it
  out for now. The call-survival goal stays open. See the revisit list.
- **Waiting for boot counting in the pinned nixpkgs.** The pinned systemd-boot has none, so
  the fall-back has to be scripted either way.
- **Replacing the server from a new image per patch.** This is the path 0021 set out to
  remove. It deletes the server first and needs Hetzner capacity at patch time.

## Consequences

- A master reboot drops calls and chat for a few minutes. The owner approves each reboot and
  types the passphrase.
- A hung boot needs an operator or a script to act. Nothing falls back by itself.
- The store registration is a required step until images bake it in.
- `cx23` boots BIOS, so this boot path does not apply to it. A `cx23` server would need its
  own check. The rehearsal uses `cpx22`, which boots UEFI.
- The LUKS unlock script is tested against a simulated prompt on the rehearsal server, not
  against the live master.

## Evidence

Observations from 2026-10-31. The "Where" column names the machine each one came from.

| Observation | Value | Where |
|---|---|---|
| Boot firmware | UEFI, systemd-boot 260.x | `cpx32` master |
| Boot firmware | UEFI | `cpx22` rehearsal server |
| Boot firmware | BIOS | `cx23` |
| Image EFI entry | one static unified kernel image, `EFI/Linux/nixos.efi` | `cpx32` master |
| Nix database paths before registration | 0 (`nix path-info --all` printed 0 while `/nix/store` had 598 entries) | `cpx32` master, read-only check; the twin also showed 0 |
| ESP size | 253 MB | rehearsal server |
| ESP used, 3 generations | 115 MB | rehearsal server |
| `configurationLimit` | 3 | rehearsal server |
| Store paths registered | 598, in about 100 seconds | rehearsal server |
| Registered reference sets matching cache.nixos.org | 507 of 508 | rehearsal server |
| Reference set not matching | one path (`getty`) whose local content (371 bytes) differs from the cached path of the same name (176 bytes); the local scan is the correct answer for it | rehearsal server |
| Hard reset to the default generation | about 20 seconds | rehearsal server |

## Unproven

- Nothing has been done on the live master beyond the read-only checks above. The
  registration, the deploy, the one-shot boot and the hard reset are proven on the
  rehearsal server only.
- The LUKS unlock mechanism (answering `systemd-ask-password` through `systemd-reply-password`)
  was proven on the throwaway twin on 2026-10-31, and `unlock-master.sh` ran against a
  simulated prompt there: correct passphrase, wrong then right, always wrong (stops after two
  sends), prompt absent, already unlocked, and a failing passphrase command. It has not run
  against the master's locked state volume.
- Call behaviour during a master reboot is unknown. No test call has run through a reboot.

## Revisit when

- The first live master patch needs manual boot menu work, or the one-shot does not boot as
  the rehearsal did.
- A call drops during a master reboot and the owner wants the edge node back on the table.
- The pinned nixpkgs ships systemd-boot boot counting. The fall-back can then be automatic.
- The LUKS unlock can be automated without putting the passphrase on a command line.
- A new server type can only boot BIOS and is needed for the Matrix stack.
