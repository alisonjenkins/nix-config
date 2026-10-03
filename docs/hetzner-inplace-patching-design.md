# Patching the Hetzner master without interrupting calls

Status: superseded by `specs/003-hetzner-inplace-patching/` and `specs/004-hetzner-encrypted-volumes/`.
Date: 2026-10-03

This was the first design sketch. Read the specs, not this page. It is kept for the reasoning
behind the decision, and it is wrong or incomplete in three places that the specs fix:

- It has no unlock step. The master's state volume is unlocked by a passphrase prompt at every
  boot, so a control-plane reboot is never unattended, and the unlock cannot go over Tailscale.
- It describes the rollback as "select the previous generation and reboot". The image's GRUB
  always boots its original generation, so the specs enable NixOS GRUB and fall back with a
  one-shot boot and a hard reset.
- It patches the master before the edge node exists. The specs bootstrap the fresh edge server
  first, then patch the master with a first-patch mode.

The plan is to patch and reboot the Hetzner master in place with deploy-rs, and to move
everything a Matrix call needs onto a separate **edge node**. The master can then reboot
during a call. The edge node is patched only when nobody is in a call.

Decision record: [ADR 0021](adr/0021-patch-hetzner-master-in-place.md).

## Why

Today the master is replaced from a new image whenever the node needs a change. A
replacement deletes the old server first and then needs a new `cpx32` to exist. It also
restarts every pod, including the Matrix SFU (LiveKit's media server). A 6-hour call
every night makes any restart a real outage.

Two things made this worse in practice:

- `cx33`, the original master type, sold out in `nbg1`, so the master moved to `cpx32` on
  2026-06-29. A replacement can fail for lack of capacity. In-place patching needs no new
  server.
- Terraform picks the most recent `purpose=k8s-node` snapshot as the master's image. Every
  new snapshot makes `tofu plan` want to replace the master.

## Goals and non-goals

Goals:

- Patch and reboot the master during a call without dropping the call or chat.
- Never depend on Hetzner having capacity at patch time.
- Every step has a go/no-go check and a way back.
- Encrypt the Matrix data volumes.
- Keep the extra cost to one small server.

Non-goals:

- Keeping a call alive while the edge node itself reboots. LiveKit has no live migration
  of a room between nodes, and Redis does not add one. See "Rejected alternatives".
- A highly available control plane. Three servers would cost about €71 a month more.
- Zero downtime for ente, monitoring or streaming while the master reboots. They are down
  for a few minutes.

## Current state

How each fact was checked is in brackets. "Read" means a live read-only query on
2026-10-03.

| Fact | Source |
|---|---|
| One control-plane node, `hetzner-k8s-master-1`, `cpx32` (4 vCPU, 8 GB), €35.49 a month | read, Hetzner API |
| k3s runs with SQLite. State is on a detachable LUKS volume. A floating IP and the Cilium Gateway Envoy (hostNetwork) live on the master | read, `lib/hetzner-node-services.nix` |
| The node uses 6.0 GB of 7.9 GB memory. Pods use 3.9 GB, k3s and the OS about 2.1 GB. Pods request 3.1 CPU cores and use about 1.2 | read, `kubectl top` |
| The SFU is one replica, `livekit-server` v1.13.7, hostNetwork, pinned to the control plane, with a 30 second grace period and no preStop hook. Its config sets `tcp_port: 30001` and `udp_port: 30002` | read, deployment spec and ConfigMap |
| LiveKit already uses Redis. `matrix-stack-valkey` (one replica, no volume, on the master) serves the SFU (db 3) and the auth service (db 2) | read, SFU config |
| Clients reach signalling through `sfu-tls-proxy` on port 30881. That proxy is hostNetwork, pinned to the control plane, and forwards to `127.0.0.1:7880`. `sfu-proxy` forwards to the node's own IP | read, ConfigMaps |
| The live master firewall allows 443, 30881/tcp, 30001/tcp, 30002/udp and the streaming ports. The workers firewall allows only SSH | read, Hetzner API |
| Matrix data is on `hcloud-volumes`: Postgres 20 GiB and Synapse media 10 GiB. Neither is encrypted | read, StorageClass and PV |
| The image ships `cryptsetup`, and the CSI driver is v2.23.0 | read |
| Terraform selects the image with `most_recent = true`. `user_data` carries the k3s token. Neither has `ignore_changes` | read, Terraform clone |
| `floating-ip-bind` skips itself unless `ROLE=server` | read, `lib/hetzner-node-services.nix` |

The local Terraform clone was behind the live firewall, so check the live state before
trusting the repo.

## Target design

Two long-lived nodes, both patched in place.

| Node | Runs | Patched |
|---|---|---|
| `hetzner-k8s-master-1` (existing `cpx32`) | k3s control plane, ente, monitoring, streaming, Karpenter, everything else | any time, including during a call |
| `hetzner-edge-1` (new, `cx23` if it fits) | Envoy gateway and the floating IP, Synapse, Postgres, matrix-authentication-service, haproxy, element-web, the auth service, the SFU with `sfu-tls-proxy`, `sfu-proxy` and Valkey, `rtc-transports-stub` | only when no call is running |

While the master reboots (a few minutes):

- The Kubernetes API is down. Pods already running on the edge node keep running.
- Calls and chat keep working, because everything they need is on the edge node.
- ente, monitoring and streaming are down. Certificate renewals and anything that needs
  the API wait.

The edge node is a static server created in Terraform from the same image, joining as an
agent. Karpenter cannot hold a minimum node count, so it is the wrong tool for a node that
must always exist.

### Edge node changes

- A new role for `floating-ip-bind`. It runs only for `ROLE=server` today.
- A firewall for the edge node with the master's Matrix rules (443, 30881/tcp, 30001/tcp,
  30002/udp). The existing firewall is attached to the master by server ID.
- `nodeSelector` or affinity for each Matrix workload, and the same for the Envoy gateway.
  The SFU, `sfu-tls-proxy` and `sfu-proxy` are pinned to the control plane today and
  `sfu-tls-proxy` assumes `127.0.0.1`.
- Memory and CPU headroom, measured before committing to `cx23`. See Phase 0.

## In-place patching with deploy-rs

`flake-modules/deploy.nix` already defines deploy-rs nodes. The master and the edge node
become two more. A patch has two parts:

1. `deploy --boot` writes the new generation to the bootloader without switching.
2. A reboot applies it, behind the gates below.

Plain `deploy` (switch without reboot) is fine for changes that need no kernel or boot
change, such as k3s flags.

### Biggest unknown: the bootloader

The image is a repart image with a hand-installed GRUB for BIOS boot. `publish-hetzner-snapshot`
writes `boot.img` and `core.img` into the raw disk itself. `switch-to-configuration boot`
on the running node may not be able to update GRUB there. Test this first, on a disposable
server (Phase 0), and never on the master.

### Terraform

Add `lifecycle { ignore_changes = [image] }` to `hcloud_server.cp`. The image is only the
starting point once nodes are patched in place. The Nix flake becomes the source of truth
for what runs on the node.

Do not add `ignore_changes` for `user_data`. That would hide real changes. A `user_data`
change, such as a new k3s token, still shows as a replacement in `tofu plan`. Open question:
how to rotate the token without a replacement. See "Open questions".

## Master reboot procedure

Run as a script, so every gate is enforced the same way each time.

Gates (abort if any fails):

1. The edge node is `Ready` and every Matrix pod is `Running` on it.
2. The master's SQLite datastore is healthy and a copy exists (the runbook's safety copy).
3. A node snapshot of the master exists from before the first in-place patch.
4. `deploy --boot` succeeded and the new generation is listed in the bootloader.
5. The Hetzner API is reachable (needed if the node does not come back).

Steps:

1. Record pod restart counts on both nodes.
2. Reboot the master.
3. Wait for the API, then for the node to be `Ready`.
4. Check that Flux reconciles, the CSI node plugin registers, and Karpenter runs.
5. Compare restart counts. The edge node's Matrix pods must show none.

Rollback, in order:

1. If the node boots but misbehaves: select the previous NixOS generation and reboot.
2. If it does not boot: Hetzner rescue mode. The state volume is separate and intact.
3. Last resort: restore from the pre-patch snapshot. That is a new server of the same type,
   so it needs capacity. This is why the first two options come first.

## Edge node patch procedure

Only when the SFU reports zero participants. The script refuses to run otherwise.

1. Check participants through the SFU's metrics endpoint (port 6789).
2. Announce a window in Matrix.
3. `deploy --boot`, then reboot.
4. Expect Matrix and ingress to be down for about 3 to 5 minutes.
5. Verify as in the master procedure, plus a test call.

## Encryption of the Matrix volumes

Existing volumes cannot be converted in place. Each is copied to a new encrypted volume.

1. Create a passphrase Secret (SOPS-encrypted in `home-cluster`) and a StorageClass
   `hcloud-volumes-encrypted` with
   `csi.storage.k8s.io/node-publish-secret-name` and `-namespace` set.
2. Prove it with a throwaway volume. This also shows how long the first mount takes on the
   edge node.
3. Move Postgres to an encrypted volume, onto the edge node, by replication. Nothing is
   copied while the database is offline, and the old volume stays untouched until the new one
   is proven. See "Postgres migration by replication" below.
4. Copy Synapse media to a new encrypted volume with a one-off job.
5. Delete the old plaintext volumes only after the data is verified.

### Postgres migration by replication

`shared-postgres` (namespace `matrix`) runs PostgreSQL 17 under CloudNativePG 1.30.1 with one
instance on a 20 GiB volume. It holds four databases: `niks3` (607 MB), `synapse` (217 MB),
`mas` (19 MB) and `app` (8 MB). That is under 1 GB, so a copy takes minutes.

Primary method: add a replica on the new storage, then switch over.

1. Set the cluster's `storage.storageClass` to `hcloud-volumes-encrypted` and add a node
   selector for the edge node. New instances take their volume from this setting. Existing
   volumes are not touched.
2. Scale to 2 instances. The operator builds the second instance from a base backup of the
   first and then streams from it. The new volume is created encrypted.
3. Wait until the replica reports zero lag.
4. Switch over (`kubectl cnpg promote`). Applications see one dropped connection and
   reconnect. The cluster name and the `shared-postgres-rw` service stay the same, so no
   application needs reconfiguring.
5. Keep the old instance and volume only until verification passes (data comparison, health
   checks and a functional check; see `specs/004-hetzner-encrypted-volumes/spec.md`, FR-006).
   Before deleting anything, set the old PV's reclaim policy to `Retain`. The StorageClass
   default is `Delete`, which would destroy the volume with its claim.
6. Once verification passes and a fresh backup of the new volume exists, destroy the old
   instance and its volume, within 24 hours. There is no fixed soak period (owner's decision,
   2026-10-03). After that, the way back is the backup.

Fallback: a second `Cluster` in replica mode (`replica.enabled`) that streams from the first,
then promote it. That needs the apps repointed (Synapse, MAS, and the niks3 DB URI), so use it
only if the primary method fails the rehearsal.

Safety steps, in order:

1. **Fix the operator status error first.** The cluster currently reports `Instance Status
   Extraction Error: HTTP communication issue`, although the pod is ready. The operator needs
   that channel to drive a switchover.
2. **Take a logical dump of every database and prove it restores.** The cluster spec has no
   `backup` section and no scheduled backup, and `firstRecoverabilityPoint` is empty. As far
   as I can tell, the Matrix and niks3 databases have no backup on this cluster today. Add a
   proper backup before any migration.
3. **Rehearse on a scratch CloudNativePG cluster.** I am not certain the operator accepts a
   changed `storageClass` on an existing cluster and uses it for new instances. The rehearsal
   settles that and the fallback decision.
4. **Run it in a no-call window.** The switchover takes seconds, but Synapse reconnects and
   chat blips.

What this covers: data at rest on Hetzner's storage, including discarded disks. What it does
not cover:

- Anyone with cluster access can read the passphrase Secret.
- The node root disk stays unencrypted. Postgres scratch files and Synapse temp files are
  `emptyDir` on it. Memory-backed `emptyDir` is an option if that matters.
- Postgres backups. Check where they go and whether they are encrypted.

The source for the StorageClass parameters is the driver's documentation. I confirmed them
from a search result, not the upstream page, so the throwaway volume is the real test.

## Rollout

Each phase has a gate. Do not start the next one until the gate passes.

| Phase | Work | Gate | Way back |
|---|---|---|---|
| 0 Measure and prove | Measure Matrix memory and CPU, including SFU CPU during a real call. Boot a disposable server from the snapshot and test `deploy --boot` and a reboot on it. Check deploy-rs reaches the node and the SSH allowlist. Confirm Valkey behaviour on restart | Edge sizing known. Bootloader update and reboot work on the test server | Delete the test server |
| 1 deploy-rs for the master | Add the node. First a switch with no reboot, then a rehearsal `--boot` and reboot with no call running. Take the pre-patch snapshot first | Master returns `Ready` with all pods back | Previous generation |
| 2 Encryption | Throwaway volume, then Postgres and media migration | Data verified on encrypted volumes | Keep the old volumes until verified |
| 3 Edge node | Terraform server, role, firewall, join as agent | Edge node `Ready`, can mount an encrypted volume | Delete the server |
| 4 Move Matrix and ingress | In a no-call window: Postgres, Synapse and the rest, then SFU and proxies, then Envoy and the floating IP | Test call works from the edge node | Move pods and the floating IP back |
| 5 Prove it | Reboot the master during a test call | The call and chat do not drop | Normal master rollback |

Phase 5 is the real acceptance test. Until it passes, do not rely on this during a real call.

## Risks

| Risk | Effect | Mitigation |
|---|---|---|
| GRUB cannot be updated in place | A reboot applies nothing, or the node does not boot | Phase 0 test server. Rescue mode and the snapshot as fallback |
| `cx23` is too small for the Matrix stack | Memory pressure on the node that must not fail | Measure in Phase 0. If it does not fit, `cpx32` is €35.49 a month |
| A call needs the API while the master is down | A client drops or fails to refresh | Phase 5 test with a real client |
| Valkey restarts and loses LiveKit room state | An active call breaks | Keep Valkey on the edge node so it never restarts with the master. Verify in Phase 0 |
| Edge node capacity gone when needed | Cannot create or replace it | It is a static server. Patch in place, so no capacity is needed |
| Master stays down | Everything but Matrix is down | Rollback order above |
| The floating IP move fails | Matrix unreachable | Do it in a no-call window with a tested rollback |

## Cost

All prices are net of VAT from the Hetzner API on 2026-10-03.

| Item | Cost |
|---|---|
| Edge node `cx23` (2 vCPU, 4 GB) | €5.49 a month |
| Edge node `cpx32` if `cx23` is too small | €35.49 a month |
| Pre-patch master snapshot | about €2.30 a month while kept (160 GB at €0.0143 a GB) |
| Test servers in Phase 0 | cents (a few hours at €0.009 to €0.06 an hour) |

## Rejected alternatives

- **Redis for live call migration.** LiveKit's documentation says a room must fit on a
  single node and describes no live migration. On shutdown a node enters draining mode and
  waits for participants to leave. Redis shares routing between nodes. It does not move a
  call. Valkey is already deployed anyway.
- **`ignore_changes` on `user_data`.** It would hide every future change to the node's boot
  configuration, not only the token.
- **A standing standby copy of everything.** A Postgres replica, a second SFU and a second
  Envoy cost more and add moving parts. Separating nodes by when they are patched is
  cheaper.
- **Karpenter surge node for Matrix.** Standbys such as a Postgres replica need time to sync,
  and a node may not be available when needed. It stays useful for other workloads.
- **HA control plane.** About €71 a month more, which is more than the problem is worth.

## Open questions

1. How to rotate the k3s token without replacing the master, given `user_data` carries it.
   One option: boot the server from the token already stored on the state volume.
2. Whether `cx23` is fast enough for a 6-hour group call. Phase 0 measures it.
3. How Element Call and the LiveKit client behave while Synapse's API path is briefly
   unreachable. Phase 5 tests it.
4. Whether the old plaintext Postgres volume can be shrunk or must be kept for rollback.

## References

- [LiveKit: distributed multi-node setup](https://docs.livekit.io/home/self-hosting/distributed/)
- [Hetzner CSI driver, encrypted volumes](https://github.com/Altinity/hetzner-csi-driver/blob/main/docs/kubernetes/README.md)
- [`hetzner-k3s-live-maintenance.md`](hetzner-k3s-live-maintenance.md), the existing runbook
