# 0021. Patch the Hetzner master in place, and keep calls on a separate edge node

- Status: Proposed
- Date: 2026-10-03

## Context

The Hetzner master (`hetzner-k8s-master-1`) is replaced from a new image whenever it needs
a change. That deletes the server first, restarts every pod, and needs Hetzner to have a
`cpx32` free. Capacity has failed here before: `cx33` sold out in `nbg1` and the master
moved to `cpx32` on 2026-06-29. The Matrix SFU is pinned to the master, and a 6-hour call
runs there most nights. Matrix data volumes are not encrypted.

Redis already runs for LiveKit (`matrix-stack-valkey`). It does not help. LiveKit's
documentation says a room must fit on one node and describes no live migration. A draining
node waits for its participants to leave.

## Decision

- **Patch in place.** Use deploy-rs with `--boot` and a gated reboot for the master. Replace
  the server only as a last resort.
- **Separate the call stack.** Put Matrix, the SFU and its proxies, Valkey, and the Envoy
  gateway with the floating IP on a static `edge` node. The master can then reboot during a
  call. The edge node is patched only when no call is running.
- **Encrypt the Matrix volumes.** A new `hcloud-volumes-encrypted` StorageClass with a LUKS
  passphrase Secret. Data is copied over, not converted.
- **Terraform ignores image changes only.** `ignore_changes = [image]` on the server. Not
  `user_data`, so a change to the node's boot configuration still shows in the plan.

## Alternatives rejected

- Redis for live call migration: it does not provide it.
- `ignore_changes` on `user_data`: it hides real changes.
- Standing standbys of Postgres, the SFU and Envoy: more cost and moving parts than
  separating nodes by patch time.
- A highly available control plane: about €71 a month more.

## Consequences

- No capacity risk for routine patching.
- One extra server: `cx23` at €5.49 a month, or `cpx32` at €35.49 if the Matrix stack does
  not fit.
- The Nix flake, not Terraform, defines what the nodes run after first boot.
- A call still drops if the edge node itself reboots, so that is done between calls.
- A control-plane reboot is never unattended: the state volume is unlocked by a passphrase
  prompt at every boot, so each one needs the owner's approval and passphrase.
- Rotating the k3s token without replacing the master is an open question.

## Evidence

Read-only queries on 2026-10-03: the SFU deployment and config, the signalling proxies, the
live Hetzner firewalls, the StorageClass and PVs, and the Hetzner server types and prices.
LiveKit's behaviour is from its distributed-mode documentation. The full list is in the
[design doc](../hetzner-inplace-patching-design.md).

Three things are unproven: that `switch-to-configuration boot` works on the hand-installed
GRUB, that `cx23` is large and fast enough, and that a call survives a master reboot. The
rollout tests each before relying on it.

## Revisit when

- Phase 0 shows GRUB cannot be updated in place, or `cx23` cannot hold the Matrix stack.
- The master reboot test drops a call.
- Hetzner offers a cheaper 8 GB type in `nbg1`, or `cx33` returns.
- LiveKit documents live migration of a room between nodes.

Move this record to Accepted once the master reboot test passes.
