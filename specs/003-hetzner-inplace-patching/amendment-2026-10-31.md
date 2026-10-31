# Amendment 2026-10-31: systemd-boot on UEFI, and the edge node deferred

Date: 2026-10-31
Decision record: [ADR 0060](../../docs/adr/0060-upgrade-the-hetzner-master-in-place-with-systemd-boot.md)
Runbook: [docs/hetzner-inplace-upgrade-runbook.md](../../docs/hetzner-inplace-upgrade-runbook.md)

The master boots UEFI, not BIOS. Its image ships systemd-boot. The edge node is deferred,
not dropped. This note lists what in this spec and in ADR 0021 is now wrong, and what replaces it.
The spec files are not edited. Read this note with them.

1. **Boot loader.** Wrong: NixOS GRUB on BIOS (plan, research section 2). Now: NixOS-managed systemd-boot on UEFI.
2. **`grub-install` on the disk layout.** Wrong: the rehearsal must prove `grub-install` is safe (research section 2). Now: no `grub-install` runs. The question is moot.
3. **Fall-back mechanism.** Wrong: `grub-reboot` and `grub-set-default` (plan, research section 3, patch-gates steps 4 and 7). Now: `bootctl set-oneshot` for the trial boot and `bootctl set-default` for the permanent default.
4. **Default setting.** Wrong: `boot.loader.grub.default = "saved"` with `grubenv`. Now: the default is set explicitly on every patch, because `bootctl set-default` overrides `loader.conf`.
5. **Boot counting.** Wrong: fall-back can rely on systemd-boot boot counting, as research section 3 implies. Now: the pinned nixpkgs systemd-boot has no boot counting. Fall-back is scripted, and the operator acts on a failed health check.
6. **Store registration.** Wrong: the running system is registered as generation 1 with no further step (plan step 0). Now: the image's Nix database is empty, so the store is registered with `register-store.sh` before step 0. Future images bake it in with `closureInfo`.
7. **Platform.** Wrong: "Two NixOS servers on Hetzner `nbg1`, BIOS boot" (plan, target platform). Now: the master is UEFI. `cx23` is BIOS and is not a valid rehearsal host. The rehearsal uses `cpx22`.
8. **Edge node.** Wrong: a `cx23` edge server is created in Terraform and bootstrapped first (plan phase C, research section 5, data-model edge attributes). Now: no edge server is created for now. The call-survival requirement (SC-001, SC-002, SC-009) is deferred, not dropped.
9. **Call-safe master reboot.** Wrong: the master reboot keeps calls up once the stack has moved to the edge (spec SC-001, plan phases E and G). Now: a master reboot drops calls and chat for a few minutes, and the owner approves each reboot.
10. **Move the stack.** Wrong: the Matrix stack, Postgres, Valkey, Envoy and the floating IP move to the edge node (plan phase E, data-model move order, research section 6). Now: none of it moves until the edge node is approved again. The move order in `data-model.md` stays as a plan for later.
11. **Cost.** Wrong: the extra cost is one `cx23` at €5.49 a month, with `cpx32` as the fallback (research section 5, SC-007). Now: no extra server is planned. SC-007 applies if the edge node returns.
12. **Edge gates.** Wrong: "Edge healthy", "Edge serving" and "Edge protected" gate the master patch (patch-gates contract, bootstrap mode). Now: these gates apply only when an edge node exists. The runbook makes a no-call check a prerequisite for the master reboot.
13. **Unlock path.** Wrong: the unlock goes through the edge machine by default (`--via edge`) (patch-gates, unlock step). Now: `--unlock-via public` from the allow-listed admin address is the path for now. `--via edge` returns with the edge node.
14. **Open questions.** Wrong: the open list includes whether `grub-install` is safe and whether `cx23` is fast enough for a call (research section 7, items 1 and 3). Now: open items are the first live master patch, the LUKS unlock automation, and call behaviour on a master reboot (ADR 0060, Unproven).
15. **Record status.** Wrong: spec 003 and ADR 0021 read as the current plan. Now: ADR 0021 carries a "superseded in part" note, and ADR 0060 is Accepted. This note does not change the status of spec 003.
