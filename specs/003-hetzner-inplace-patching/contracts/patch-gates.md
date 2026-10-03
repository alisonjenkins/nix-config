# Contract: patch gates and steps

What the patch scripts check and do. A script that fails a gate changes nothing and exits non-zero.
Every line carries an ISO 8601 UTC time, the machine, the step and the result, and errors name the
failing operation and its inputs (constitution IV). The scripts live in
`scripts/hetzner-patch/`. They use `scripts/hetzner-volume-verify/check-no-call.sh` from spec 004.

## Gates for both machines

| Gate | Pass condition |
|---|---|
| Target reachable | SSH over Tailscale works and the machine reports its current generation. For the control-plane machine this applies before the reboot only; it is not on the tailnet between the reboot and the unlock (see "The unlock step") |
| Hetzner API | the API answers a read-only call and `HCLOUD_TOKEN` is set. The snapshot check and the hard reset depend on it |
| Build | `nix build` of the target closure succeeds, with its evaluation clean |
| Snapshot | a Hetzner server snapshot of the machine exists from before the first in-place patch, and is less than 30 days old |
| Cluster healthy | all nodes `Ready`, Flux reconciled, no failing core pods |
| Edge healthy | the edge node is `Ready`. Once the Matrix stack has moved there, also every Matrix pod `Running` on it with no restarts in the last hour |
| No servers touched | the plan makes no server create or delete call |
| Previous generation in the menu | after the install, the bootloader menu lists the generation that was running before the patch. On a machine that has never been patched in place, step 0 first registers the running system as a generation. If the entry is still absent, the patch aborts |

## Extra gates: the call machine

| Gate | Pass condition |
|---|---|
| No call | `check-no-call.sh` reports `calls=0` |
| No call, again | the same check passes again immediately before the reboot |
| Window announced | a notice was posted in the household's chat at least 10 minutes before |

## Extra gates: the control-plane machine

| Gate | Pass condition |
|---|---|
| Edge serving | a test message and a join to a test room succeed through the edge node |
| Edge protected | the edge pods have the 900 second tolerations, and there is no pending rollout there |
| Owner present | the owner has approved this run and supplied the unlock for it |
| Datastore copy | the state volume's datastore safety copy exists and is recent |

## Bootstrap mode (the control-plane machine's first patch only)

The first patch introduces the bootloader change, and the Matrix stack has not moved to the edge machine yet.
With `--first-patch` the script skips only the two edge gates "Edge serving" and "Edge protected". It still
requires the edge machine `Ready`, the snapshot, the owner's approval, a passing no-call check, and the
"Previous generation in the menu" gate. It is refused without `--approve`. It is not used again after the
acceptance test is set up.

## Steps: either machine

0. If the machine has no profile generation for the running system (`/nix/var/nix/profiles/system` missing or
   not including it), register it: `nix-env -p /nix/var/nix/profiles/system --set $(readlink -f /run/current-system)`.
   This is what makes "the previous generation" exist the first time.
1. Record the pods' restart counts on both machines, and the current generation.
2. `deploy --boot` to install the new generation.
3. Check that the new boot entry exists.
4. Set the new entry as a one-shot (`grub-reboot`). The saved default stays the old generation.
5. Reboot. For the master, answer the unlock prompt (below).
6. Wait for SSH, then for the machine to report healthy. The limit is 10 minutes for the call machine
   and 15 for the control plane.
7. If healthy, make the new entry permanent (`grub-set-default`).
8. If not healthy by the limit, hard reset through the Hetzner API. The machine boots the previous
   generation by itself. Record `rolled-back`.
9. Compare restart counts. For the master's patch, the edge node's Matrix pods, its Cilium agent,
   its Envoy proxy and its CoreDNS copy must show no restarts. Check Cilium, Envoy and CoreDNS
   health immediately after the API returns.
10. Write the run record.

## The unlock step (control-plane machine only)

- The master is not on the tailnet until it is unlocked, because Tailscale's state is on the locked volume. The
  script therefore connects by a jump host through the edge machine over the private network (`--via edge`, the
  default), or by the master's public address from the allow-listed admin address (`--via public`). It never
  uses the master's Tailscale name for the unlock. Tailscale is used again after the unlock.
- The script waits until the unlock prompt is pending. It does not answer before the owner approves.
- The owner approves, and the passphrase is read from the password manager at that moment.
- The passphrase is sent to the prompt over SSH. It is never printed, logged, put on a command line,
  or stored.
- A wrong passphrase makes the prompt ask again (the unit loops). The script allows two attempts,
  then stops and asks the owner.

## Never

- The script does not create or delete a server.
- It does not reboot the call machine while any participant is present.
- It does not reboot the control plane without the owner's approval for that run.
- It does not make a new generation the default before the health checks pass.
