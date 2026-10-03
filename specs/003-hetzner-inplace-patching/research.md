# Research: Patch the Hetzner control plane without interrupting calls

Date: 2026-10-03. Each decision names its evidence, a confidence, and what is unproven.
Unproven points are rehearsal steps in `plan.md`, not assumptions.

"Read" means a live read-only query or a read of the repositories. "Docs" means a research
sub-agent's report from upstream documentation, which is second-hand. The Terraform facts come
from `~/git/terraform` (the real clone, up to date at 2026-10-02), not the stale scratch copy.

## 1. In-place patching with deploy-rs

**Decision**: Define the control-plane machine and the call machine as deploy-rs nodes in
`flake-modules/deploy.nix`, both on the existing `hetzner-karpenter-node-amd64` configuration,
reached over Tailscale. Use `deploy --boot` (update the bootloader, do not activate) followed by a
scripted reboot.

**Evidence**:

- `deploy --boot` exists. It runs `switch-to-configuration boot` and has been in deploy-rs since
  PR 176 (2022-12-29); the locked revision is far newer (docs, high; read, `flake.lock`).
- With `--boot` there is **no confirmation window and no timed rollback**. Magic rollback only runs
  without `--boot`. Auto-rollback covers a failed activation script, not a bad boot (docs, high;
  issue 186). deploy-rs does not reboot, so the reboot is ours.
- The existing nodes in `flake-modules/deploy.nix` use `user = "root"` and `activate.nixos`
  (read). The Hetzner nodes follow that pattern, with `sshUser = "ali"` (wheel, passwordless sudo
  is configured in the image, read) and the Tailscale name as `hostname`. The master is already on
  the tailnet as `hetzner-k8s-master-1` (read, Tailscale machine page), so public SSH is not needed.
- Both nodes share one NixOS configuration, and the role comes from user data at boot (read), so
  one closure serves both. `hetznerSystems` is already exported as `flake.nixosConfigurations`
  (read).

**Plain `deploy` (switch, no reboot)** has magic rollback and suits changes that need no new
kernel or boot entry. A switch that changes the k3s unit restarts k3s for a minute or two, and pods
survive because the unit uses `KillMode=process` (read).

**Alternatives considered**: Replacing the server from a new image, which is today's path and the
reason for this feature. `nixos-rebuild --target-host`, rejected because the repository already
standardises on deploy-rs.

## 2. The bootloader does not update in place today (finding)

**Finding (read, high)**: `lib/hetzner-repart-image.nix` sets `boot.loader.grub.enable =
lib.mkForce false` and `boot.loader.systemd-boot.enable = lib.mkForce false`. The image carries a
hand-built GRUB: `boot.img` in the MBR, `core.img` in the `bios_grub` partition, and a **static**
`grub.cfg` that says `linux <kernel store path> init=<toplevel>/init`, for the one generation that
was built into the image. NixOS never rewrites it. A reboot therefore always starts the image's
original generation, whatever generations later deploys install.

A second detail: the image mounts the 256 MB ESP at `/boot` (`fileSystems."/boot"` by label), while
the hand-built `core.img` looks for its config on the root filesystem's `/boot/grub`. At runtime the
ESP mount hides that directory. A NixOS bootloader that writes to `/boot/grub` would write to the
ESP, which the hand-built `core.img` never reads.

**Decision**: Enable NixOS's own BIOS GRUB for the running system, with `boot.loader.grub.device`
set to the real disk, so the first activation runs `grub-install` and rebuilds `core.img` for the
layout NixOS actually mounts. After that, `switch-to-configuration` writes `grub.cfg` and copies
kernels for each generation.

**Evidence**:

- `install-grub.pl` rewrites `grub.cfg` every run and runs `grub-install` when its state changed or
  there is no previous state. The first run on this hand-installed machine will therefore run
  `grub-install` (docs, medium-high).
- With `device = "nodev"` it skips `grub-install` and only writes the menu. That would leave the
  hand-built `core.img` pointing at the wrong place (docs, medium-high; read).
- BIOS GRUB with `/boot` on a FAT partition is valid, and `grub-install` includes the needed
  modules when it builds `core.img` (docs, medium; background knowledge).
- Each generation's kernel and initrd are copied to `/boot`. The ESP is 256 MB, so
  `configurationLimit` must be small (3 to 4) (read: 256 MB; estimate: about 35 MB a generation).

**Unproven, so rehearsed first on a disposable server built from the same snapshot** (Phase 0):

1. That `grub-install` succeeds on this disk layout and the machine still boots.
2. That a new generation boots, and that kernel and initrd copies fit the ESP.
3. That `switch-to-configuration boot` aborts cleanly if `grub-install` fails (docs, low).

**Alternatives considered**:

- A tiny custom `system.build.installBootLoader` that only rewrites `grub.cfg` for the existing
  `core.img`, with `/boot` moved off the ESP. It avoids touching the MBR, but it is custom code to
  maintain. It is the fallback if rehearsal shows `grub-install` is unsafe here.
- Rebuilding the image per change. That is a server replacement, which this feature removes.

## 3. A bad generation must fall back by itself

**Finding (docs, medium-high)**: NixOS has no boot counting for GRUB. Only systemd-boot has it
upstream. deploy-rs `--boot` gives no rollback after the reboot. A generation that hangs at boot
leaves no SSH and no console.

**Decision**: Use GRUB's one-shot default. Set `boot.loader.grub.default = "saved"`. Before the
reboot, run `grub-reboot` for the new entry. The next boot uses the new generation once, and the
boot after that reverts to the saved default, which is the previous generation. After the node is
healthy, run `grub-set-default` to make the new generation permanent. A hung boot is then recovered
by a hard reset through the Hetzner API (no console, no rescue mode), which boots the old
generation.

**Evidence**: `grub-reboot` and the `saved` default are documented, and one-shot fallback is the
standard A/B pattern (docs, medium; the Hetzner rescue-mode recovery guide uses `grub-reboot`).

**Unproven**: whether the GRUB built by NixOS includes `load_env` and `save_env` (it installs its
modules to `/boot/grub`, so they are loadable) and whether `grubenv` on the ESP's FAT is writable by
GRUB. Rehearsed in Phase 0, including a deliberate hang and a hard reset.

**Also set** `boot.loader.timeout` to about 10 seconds, so a human at the Hetzner web console can
pick an older entry if everything else fails.

**Unproven and important (found in the analysis)**: the fallback needs the previous generation to be a menu
entry. The image config does not register the image's original system as a profile generation, so on a machine
that has never been patched in place there may be no previous entry. The patch procedure's step 0 registers the
running system as generation 1 before the first deploy, and the Phase 2 rehearsals confirm the menu then lists
both. The gate "Previous generation in the menu" fails the patch if it does not.

**Recovery layers, in order**: (a) before the reboot, `switch-to-configuration` or
`nixos-rebuild --rollback` to the previous generation; (b) after a hung boot, a hard reset boots
the old generation by itself; (c) the Hetzner web console and GRUB menu; (d) rescue mode, which
keeps the state volume intact; (e) restore from the pre-patch server snapshot, which is a new
server of the same type and so needs capacity. Layers (a) to (d) need no new server.

## 4. The control-plane reboot needs the owner's passphrase (finding)

**Finding (read, high)**: `k3s-state-volume` in `lib/hetzner-node-services.nix` opens the LUKS state
volume with `systemd-ask-password`, answered "post-boot SSH" by the operator, with
`TimeoutStartSec=infinity`. The passphrase is never on the machine. k3s does not start until it is
answered. Nodes with `ROLE` other than `server` skip this unit.

**Consequences**:

- A control-plane reboot is never unattended, and the spec now says so (Assumptions).
- The call machine runs as an agent, has no such volume, and reboots unattended.
- Between the reboot and the unlock the master is not on the tailnet, because `/var/lib/tailscale` is bound from
  the locked volume (read, `k3s-state-volume`). The unlock is reached over the private network through the edge
  machine as a jump host, or by the master's public address from the allow-listed admin address (the firewall
  allows SSH only from that one address). Tailscale is used before the reboot and after the unlock.
- The reboot script waits for SSH, then answers the prompt with a passphrase the owner approves
  for that run. The passphrase comes from the password manager at run time and is never printed or
  stored.

**Decision**: A script `unlock-master.sh` answers the pending prompt. Two ways are possible and are
rehearsed on the disposable server with a throwaway LUKS volume: piping the passphrase to
`systemd-tty-ask-password-agent --query` over SSH, or writing the reply file with
`systemd-reply-password`. Whichever works is used.

**Alternatives considered**:

- Storing the key on the machine, or in the metadata service. Rejected: it defeats the point of
  encrypting the state volume.
- A TPM. Hetzner Cloud servers have none.
- Keeping the passphrase in Terraform variables for unlocking. Rejected for the same reason.

## 5. The call machine (edge node)

**Decision**: A static server `hetzner-edge-1` in Terraform, from the same snapshot with
`ROLE=agent`, joined through the same bootstrap as the Karpenter workers. It is attached to the
private network at a fixed address, placed in the existing spread placement group so it lands on a
different physical host from the master, and given its own firewall.

**Evidence** (read):

- The master is `hcloud_server.cp` with a `hcloud_floating_ip_assignment`, a LUKS state volume and
  user data that carries `ROLE=server`. The workers firewall allows only SSH, and nothing public.
- The existing master firewall allows 443/tcp, 30881/tcp, 30001/tcp, 30002/udp for Matrix, SSH from
  one address, and the streaming ports (read, Hetzner API).
- The Hetzner API lists `cx23` (2 vCPU, 4 GB, €5.49 a month) as available in `nbg1` and `fsn1`.
  `cx33` is sold out in every location (read). The master's own type, `cpx32` (€35.49), is available
  (read).
- Matrix pods use about 1.2 GB of memory (Synapse 141 MB, Postgres 419 MB, SFU 89 MB, the rest
  small) plus roughly 0.7 GB for per-node agents (Cilium 202 MB, Tetragon 166 MB and others)
  (read, `kubectl top`). That fits 4 GB with little spare, so the type is confirmed by measurement
  in Phase 0 (owner's rule: stop and ask if too small).
- The server is created once. That one-time creation needs capacity, which routine patching never
  does again.

**Fallback types, in cost order**: `cx23` (€5.49), `cpx22` (€19.49, same size), `cpx32` (€35.49,
8 GB). Moving to a larger type needs the owner's approval (spec FR-011).

**Terraform changes** (in `~/git/terraform/hetzner/`): a new `hcloud_server.edge`, its
`hcloud_server_network`, a new `hcloud_firewall.edge`, the placement group, and
`ignore_changes = [image]` on both servers (section 8). The floating IP assignment is repointed at
the edge server in one step near the end.

## 6. What moves to the edge node

Read, 2026-10-03:

| Component | Today | Change |
|---|---|---|
| SFU `matrix-stack-matrix-rtc-sfu` | `nodeSelector` control-plane, hostNetwork | select the edge node |
| `sfu-tls-proxy` | `nodeSelector` control-plane, proxies to `127.0.0.1:7880` | select the edge node; it still shares a host with the SFU |
| `sfu-proxy` | no selector, forwards to its own node's IP on 7880 | **must be pinned to the edge node**, or it forwards to a host with no SFU |
| `rtc-transports-stub`, haproxy, MAS, auth service, element-web | no selector | pin to the edge node |
| Synapse main, and the Postgres cluster | no selector, on the master | pin to the edge node (Postgres by replication, section 7) |
| Valkey | no selector, no volume | pin to the edge node, so it never restarts with the master |
| Envoy data plane `envoy-ente-platform-...` | `nodeSelector` control-plane, hostNetwork, 1 replica, from `EnvoyProxy` `eg-proxy-config` | select the edge node; it serves every app behind the gateway |
| CoreDNS | 1 replica, managed by the k3s add-on controller | add a second Deployment sharing the `kube-dns` label, pinned to the edge node |
| Floating IP and its binding unit | bound only when `ROLE=server` | a new `ROLE=edge` binding, and the assignment moved in Terraform |
| MediaMTX, OvenMediaEngine, Minecraft proxy, cloud controller manager | control-plane selectors | stay on the master (streaming and game are not part of the guarantee) |

CoreDNS is managed by k3s, so patching its replica count from Flux would be reverted. A second
Deployment that carries the same label is not managed by k3s and the Service balances across both.

The edge node gets a taint such as `workload=edge:NoSchedule`, so only the listed pods land there,
and those pods carry the toleration and the selector. DaemonSets tolerate it already.

## 7. Moving the database and the volumes

**Decision**: Reuse the method of `specs/004-hetzner-encrypted-volumes/` a second time. The
Postgres cluster gets an instance on the edge node by replication, then a switchover, then the old
instance is removed. The Synapse media claim is an encrypted RWO volume, so the pod simply
reschedules and the volume detaches from the master and attaches to the edge node.

**Evidence and unproven points**:

- The database already sits on an encrypted volume by then (spec 004 lands first, owner's decision).
- Pinning the new instance to the edge node needs `spec.affinity.nodeSelector`. Whether a changed
  affinity restarts the existing primary is unverified (docs, low-medium, from the 004 research).
  Rehearse on a scratch cluster first. This feature adds that question to the rehearsal.
- A volume attach to a new node can wait on the storage plugin's registration. The edge node exists
  long before the move, so that delay is over by then (read: it took about 9 minutes on a fresh
  node).

## 8. Terraform stops replacing servers on a new image

**Finding (read)**: the master's image comes from `data.hcloud_image.k8s_node` with
`most_recent = true`, with no lifecycle rule. Every new `purpose=k8s-node` snapshot changes
`hcloud_server.cp.image`, and the plan wants to replace the master.

**Decision**: `lifecycle { ignore_changes = [image] }` on both the master and the edge server, and
nothing else. The Nix flake becomes the source of truth for what runs on them after first boot.
`user_data` stays tracked, so a change to the boot configuration still shows in the plan. This is
the owner's earlier ruling.

**Consequence**: how to rotate the k3s token without replacing the master remains an open question
(section 11). It is outside this feature's goals.

## 9. Behaviour while the control plane is down

Docs, from a research sub-agent, mostly medium confidence and not verified in the clusters' own
version:

- Pods already running on the edge node keep running. Probes continue locally. New pods are not
  scheduled and endpoints are not updated. Projected service-account tokens are not refreshed, but a
  few minutes is far below the one hour lifetime (high on the kubelet, medium on the token detail).
- After the control plane returns, the node lifecycle controller should not evict healthy pods: the
  node-monitor grace period is 40 seconds, the eviction toleration is 300 seconds, and the kubelet
  renews its lease about every 10 seconds (medium). Edge pods still get an explicit toleration of
  900 seconds for `unreachable` and `not-ready` as cheap insurance.
- Cilium keeps service load-balancing and policy for already-programmed endpoints, because the
  eBPF maps are pinned. An agent **restart** during the outage can block on the API and disrupt
  traffic for 30 to 60 seconds (docs, medium; Cilium issues 28089 and 34653). The procedure never
  restarts the agent on the edge node during the window, and checks it right after the return.
- The Envoy data plane keeps its last configuration while the Envoy Gateway controller or the API
  is down. If an Envoy pod restarts while the controller is down, it comes up with nothing to serve
  (docs, medium). The edge node therefore must not restart that pod during the window.
- CoreDNS serves from its in-memory cache. A restart loses it. A copy on the edge node avoids both
  the loss of the master's copy and a restart (docs, medium-high).
- LiveKit's documentation says Redis is for multi-node mode and does not state what happens to an
  established call if Redis is briefly unreachable (docs, high on the first, nothing on the second).
  Valkey on the edge node never restarts with the master, so the question does not arise in this
  design. Established media is direct to the SFU. On a signal loss the client tries a resume first
  and then a full reconnect (docs, medium).

**The most likely failure** is a pod or agent on the edge node restarting during the outage with
nothing to resync from. The mitigation is a short outage, no restarts on the edge node during it,
and a health check on Cilium, the Envoy proxy and CoreDNS as soon as the API returns.

## 10. Shared tooling

The no-call check is `scripts/hetzner-volume-verify/check-no-call.sh`, written in spec 004 (tasks
T019 and T020). This feature calls it and does not duplicate it (constitution V). It fails closed.

## 11. Open points

0. **Order of the first live changes.** The first `grub-install` on a real machine happens on the fresh edge
   server, before the master is touched. The master's first patch uses bootstrap mode, because the Matrix stack
   has not moved yet.
1. **Whether the first `grub-install` is safe on this layout.** Settled by the Phase 0 rehearsal on a
   disposable server. If not, switch to the custom `installBootLoader` fallback.
2. **How to answer the unlock prompt non-interactively** (the tty agent, or the reply file). Settled
   by the same rehearsal with a throwaway LUKS volume.
3. **Whether `cx23` is large and fast enough for a 6 hour group call.** Measured with a real call on
   the edge node, and the owner decides if it is not.
4. **Whether a changed Postgres `affinity` restarts the primary.** Rehearsed on a scratch cluster.
5. **Rotating the k3s token without replacing the master** (the `user_data` question). Not in this
   feature.
6. **Whether Cilium's agent on the edge node survives a control-plane reboot without a restart.**
   Checked in the acceptance test, with a recorded measurement.
