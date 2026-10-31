# Hetzner master in-place upgrade runbook

Status: not yet run on the live master. The rehearsal on a throwaway `cpx22` is the only
proof so far. Decision record: [ADR 0060](adr/0060-upgrade-the-hetzner-master-in-place-with-systemd-boot.md).

This runbook is for the operator who patches and reboots `hetzner-k8s-master-1` (server ID
`165673643`, `cpx32`, UEFI). The owner must be present for every reboot, because the state
volume unlocks with a passphrase at each boot. A reboot drops calls and chat for a few minutes.

## Prerequisites

Check each item before the run. Stop at the first one that fails.

1. **Owner present.** The owner approves this run and has the LUKS passphrase in the password
   manager.
2. **No call running.** `scripts/hetzner-volume-verify/check-no-call.sh` (spec 004) reports `calls=0`. Post a notice in the
   household chat at least 10 minutes before the reboot.
3. **Hetzner API works.** `HCLOUD_TOKEN` is set, and this read-only command returns the master:

   ```sh
   hcloud server describe 165673643
   ```

4. **SSH over Tailscale works.** `ssh ali@hetzner-k8s-master-1 true` exits 0.
5. **A snapshot exists from before the first in-place patch, and it is under 30 days old.**
   Create one if it does not:

   ```sh
   hcloud server create-image 165673643 --type snapshot --description "pre-patch-$(date -u +%Y%m%dT%H%M%SZ)"
   ```

   Check that the image is listed and `available` before the run. The flags were checked against
   `hcloud server create-image --help`. The command has not been run against the master.
6. **The target closure is built.** Build the toplevel from the flake that the run deploys:

   ```sh
   nix build .#nixosConfigurations.hetzner-k8s-master-1.config.system.build.toplevel --no-link --print-out-paths
   ```

   Keep the printed `/nix/store/...` path. It is the `--toplevel` argument. The flags were
   checked against `nix build --help`. The command has not been run against the master's flake revision.
7. **The rehearsal passed.** See the next section. Do not skip it for a new flake revision.

## Rehearsal on a throwaway server

The rehearsal runs on a throwaway `cpx22`. Do not use `cx23` for it. A `cx23` boots BIOS, so
it does not test the UEFI path that the master uses.

The rehearsal needs the owner's approval to create and later delete the throwaway server.
Record its ID as `TWIN_ID` and its address as `TWIN_HOST`. The rule against creating or deleting
servers covers the master only.

1. Check the store registration state. It must be `0` before the first registration:

   ```sh
   ssh ali@TWIN_HOST 'nix path-info --all | wc -l'
   ```

2. Register the store. Generate the registration on the target, then load it into the Nix
   database:

   ```sh
   ssh ali@TWIN_HOST 'bash -s -- /nix/store' < scripts/hetzner-patch/register-store.sh > reg.txt
   ssh ali@TWIN_HOST 'sudo nix-store --register-validity' < reg.txt
   ```

   Check the count again. Expect about `598` on the rehearsal image. Do not run the
   registration when the count is not `0`.

3. Record the running system as the first generation:

   ```sh
   ssh ali@TWIN_HOST 'sudo nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"'
   ```

4. Copy the new toplevel to the twin. The copy needs `--no-check-sigs`, because the
   signing key is not in the target's trusted set:

   ```sh
   nix copy --no-check-sigs --to ssh-ng://ali@TWIN_HOST <toplevel>
   ```

5. Set the new generation as the profile, and install its boot entry:

   ```sh
   ssh ali@TWIN_HOST "sudo nix-env -p /nix/var/nix/profiles/system --set <toplevel> && sudo <toplevel>/bin/switch-to-configuration boot"
   ```

6. Confirm the new entry exists. Note its ID, for example `nixos-generation-2.conf`:

   ```sh
   ssh ali@TWIN_HOST 'sudo bootctl list'
   ```

7. Set the new entry as a one-shot, then reboot:

   ```sh
   ssh ali@TWIN_HOST 'sudo bootctl set-oneshot nixos-generation-2.conf && sudo systemctl reboot'
   ```

8. After the server answers, check that the one-shot booted and that the default did not
   change:

   ```sh
   ssh ali@TWIN_HOST 'sudo bootctl status | grep -E "Current Entry|Default Entry"'
   ```

9. Test the fall-back. Set the new entry as a one-shot again, do not set the default, and reset
   the server as if the health check had failed. Time it. The old default generation should boot.
   Rehearsal measured about 20 seconds:

   ```sh
   ssh ali@TWIN_HOST 'sudo bootctl set-oneshot nixos-generation-2.conf'
   hcloud server reset TWIN_ID
   ```

10. Confirm the default boots, and set it explicitly:

    ```sh
    ssh ali@TWIN_HOST 'sudo bootctl set-default nixos-generation-2.conf'
    ```

11. Delete the throwaway server when the owner agrees. Record the result in the run notes.

## Patching the master

Run this from a machine with the `scripts/hetzner-patch/` scripts and the Hetzner API token.
The owner must be on hand for the unlock prompt.

```sh
scripts/hetzner-patch/patch-node.sh --host hetzner-k8s-master-1 --server-id 165673643 --toplevel <path> --approve --unlock-via public --health-cmd 'k3s kubectl get --raw=/readyz'
```

| Flag | Meaning |
|---|---|
| `--host` | Tailscale name used for SSH before the reboot |
| `--server-id` | Hetzner server ID, used for the snapshot check and the hard reset |
| `--toplevel` | `/nix/store` path of the target system, from prerequisite 6 |
| `--approve` | Owner approval for this run. Without it the script refuses |
| `--unlock-via public` | Unlock over the master's public address from the allow-listed admin address. The unlock cannot use Tailscale, because the state volume is locked |
| `--health-cmd` | Command that must succeed on the new generation before the default changes |
| `--force-reboot` | Always reboot, even when the kernel, initrd and modules are unchanged (see "Rebootless patches") |

The script runs the gates from [spec 003's patch contract](../specs/003-hetzner-inplace-patching/contracts/patch-gates.md),
then:

1. Registers the running system as a generation, if the profile does not have one.
2. Deploys the new generation with `--boot`.
3. Checks that the new boot entry exists.
4. Sets the new entry as a one-shot, then reboots.
5. Unlocks the state volume with `unlock-master.sh` (see "Unlock" below). The unlock answers
   only after the owner approves, and the passphrase comes from the password manager at that moment.
6. Waits up to 15 minutes for SSH and a passing health command.
7. Sets the new entry as the default with `bootctl set-default`.
8. Writes a run record.

### Exit codes

| Code | Meaning | What the operator does |
|---|---|---|
| 0 | Patched and healthy. The new generation is the default | Record the run. Compare the master's pod restart counts with the values before the run. Check Cilium, Envoy and CoreDNS health. |
| 2 | Refused at a gate. Nothing remote changed. A harmless store registration or profile step may already have run, and the script reports it | Read the failing gate in the output, fix it, and run again. |
| 3 | Unhealthy, rolled back successfully. A hard reset booted the prior generation | Record `rolled-back`. Confirm with `k3s kubectl get --raw=/readyz` and the generation in the run record. |
| 4 | Unhealthy, and the rollback failed | Manual recovery is needed. Start at layer 2 of "Recovery layers" below. |

### Rebootless patches

If the target's kernel, initrd and kernel modules are the same store paths as the booted
system's, `patch-node.sh` does not reboot and no unlock is needed. It runs
`switch-to-configuration test` as the transient unit `hetzner-patch-switch.service`, so the
switch survives an ssh drop and a unit that never finishes cannot hang the script. Then:

1. It polls for `current-system` and the health command, as in the reboot path.
2. It reads the unit's result. A failed switch counts as unhealthy.
3. If the switch is still waiting on queued units after 60 s, it stops the unit to free the switch lock.
4. Only now does it write the generation and boot entry, then `bootctl set-default`.

Unhealthy: the script switches back to the prior generation the same way, with no reboot and no
hard reset. It falls back to `rollback.sh` only if that fails. Nothing was written to the profile
or the ESP before the host was healthy, so there is nothing to clean up.

Kernel updates still reboot. A kernel CVE fix can be loaded as a livepatch module on the
x86_64 image (`CONFIG_LIVEPATCH=y`, `modules/hetzner`). `scripts/livepatch` scaffolds, builds and verifies a
hand-written module; see the `kernel-livepatch` skill. Proven on the twin on 2026-10-31 with the kernel's
`livepatch-sample` module and with a generated `version_proc_show` patch.

The booted boot entry can be pruned by `configurationLimit` after a few live patches. The script
then uses the default entry as the rollback target, and never sets the default to an entry whose
file is gone.

### Unlock

`unlock-master.sh` unlocks the state volume and waits until the host answers SSH.

```sh
unlock-master.sh --host HOST --via public|edge [--jump JUMPHOST] [--approve] [--wait-prompt SECS=600] [--wait-unlock SECS=120] [--max-attempts N=2]
```

The passphrase comes from the environment variable `UNLOCK_PASSPHRASE_CMD`. Its default is
`op item get ifnbgrbsk6ltkwry3g7r4obtwi --fields label=password --reveal`. The script never prints
the passphrase or puts it on a command line.

The script waits for the pending `systemd-ask-password` prompt. It reads the `Socket=` value from
the matching `/run/systemd/ask-password/ask.*` file, then sends the passphrase on stdin to
`systemd-reply-password 1 <socket path>`. This mechanism was proven on the throwaway twin on 2026-10-31.

| Code | Meaning |
|---|---|
| 0 | Unlocked. The host answers SSH |
| 2 | Refused, or not approved with `--approve` |
| 3 | The unlock prompt never appeared within `--wait-prompt` |
| 4 | Not unlocked after `--max-attempts` attempts |
| 5 | The passphrase command failed or returned an empty value |

### Rollback

`rollback.sh` hard resets the server through the Hetzner API, then waits for it to boot the
expected generation.

```sh
rollback.sh --host HOST --server-id ID --expect-generation STOREPATH [--wait SECS (default 300)]
```

| Code | Meaning |
|---|---|
| 0 | The host is back on the expected generation |
| 4 | The host is not back on the expected generation within `--wait` |

## Apply-day checklist

For the first run on the real master. Each line is one action; stop at the first one that fails.
The master serves live Matrix calls, so pick a window the owner accepts: a reboot-path patch
drops them for several minutes, a rebootless one should not.

1. Owner confirms the window and is on hand for the unlock prompt (reboot path only).
2. Snapshot is under 30 days old (prerequisite 5). If not, take one and wait for `available`.
3. `--toplevel` is built and in the local store (prerequisite 6). Note its kernel, initrd and
   modules paths against the master's `/run/booted-system`; they decide rebootless or reboot.
4. Export `KUBECONFIG` for the master so gate G5 runs. On the twin it was skipped, so G5 has not
   been seen passing end to end here.
5. Record before-values: `k3s kubectl get pods -A` restart counts, `uname -r`, `cat /proc/sys/kernel/random/boot_id`.
6. Dry run, which changes nothing:
   `scripts/hetzner-patch/patch-node.sh --host hetzner-k8s-master-1 --server-id 165673643 --toplevel <path> --dry-run`
   Read the plan: it says whether the live or the reboot path applies.
7. Refusal check: run the same command without `--approve` and without `--dry-run`. It must exit 2 at G1.
8. Real run: the command in "Patching the master", with `--approve`.
9. Exit 0: compare restart counts, check Cilium, Envoy and CoreDNS, confirm `bootctl status` shows the new default.
10. Exit 3: confirm `/readyz`, record `rolled-back`. Exit 4: go to "Recovery layers" layer 2.
11. After a rollback by hard reset the k3s volume stays locked until the unlock runs again.

Dry run, no-approve refusal and the gates were repeated against the twin on 2026-10-31 and behave
as described; the twin never exercises the real LUKS volume, Cilium or Matrix.

## Recovery layers

Work through these in order. Stop at the first one that brings the master back on its
previous generation.

1. **Hard reset to the default generation.** Run `rollback.sh` (see "Rollback"), or
   `hcloud server reset 165673643` by hand. The default
   generation boots, which is the old one if the default was not changed. Rehearsal measured
   about 20 seconds. Then unlock with the owner present.
2. **Hetzner web console and boot menu.** Open the server's console in the Hetzner web UI.
   The systemd-boot menu lists the old generation. Select it. This needs the console and the
   menu timeout to allow a choice. Untested on the master.
3. **Rescue mode.** Boot the Hetzner rescue system. Unlock the root volume with the owner's
   passphrase, mount it, and run `bootctl set-default` on the old entry from a chroot. Then
   reboot normally. Untested on the master.
4. **Snapshot restore, last.** Restore the pre-patch snapshot. This needs Hetzner capacity for
   a new server, so it can fail. A restore replaces the server and changes its ID. It also
   loses everything written after the snapshot. The owner decides before this step.

## What never to do

- Never create or delete `hetzner-k8s-master-1` (server ID `165673643`). The patch path
  exists so that a replacement is never needed.
- Never set the default to a generation before it passes the health check.
- Never skip the snapshot gate on the master.
- Never answer the unlock prompt without the owner. Never put the passphrase on a command
  line, in a log, or in a file.
- Never rely on `loader.conf` alone to change the default. `bootctl set-default` writes an
  EFI variable that overrides it. Set the default explicitly on every patch.
