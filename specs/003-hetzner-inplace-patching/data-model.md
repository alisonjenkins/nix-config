# Data model: Patch the Hetzner control plane without interrupting calls

Entities, their fields, and the states a patch moves through. Facts are from the live cluster and
the repositories on 2026-10-03.

## Machines

The spec's "call machine" is the edge machine here. The label `node-role=edge` and the taint
`workload=edge:NoSchedule` are defined once, in this document. Terraform's user data sets them and the
manifests select on them.

| Machine | Role | Runs | Volume unlock | Patched | Reboot |
|---|---|---|---|---|---|
| `hetzner-k8s-master-1` | `server` (control plane) | k3s, ente, monitoring, streaming, the Minecraft proxy, Karpenter, the cloud controller manager | LUKS state volume, answered over SSH at every boot | any time, including during a call | needs the owner's passphrase |
| `hetzner-edge-1` (new) | `agent` | Matrix and its database, the SFU and its proxies, Valkey, the Envoy data plane, a CoreDNS copy, the floating IP | none (encrypted data volumes unlock through the CSI driver) | only when no call is active | unattended |

Both machines boot the same NixOS configuration, `hetzner-karpenter-node-amd64`. The role comes from
user data at first boot.

## Edge node attributes

| Field | Value |
|---|---|
| Server type | `cx23` (2 vCPU, 4 GB), fallbacks `cpx22`, `cpx32`; larger needs owner approval |
| Location | `nbg1`, same as the master, the state volume and the floating IP |
| Private address | a fixed address in the platform subnet, chosen next to the master's |
| Placement | the existing spread placement group, so a different physical host from the master |
| Firewall | its own: 443/tcp, 30881/tcp, 30001/tcp, 30002/udp, SSH from the admin address |
| Kubernetes labels and taint | label `node-role=edge`, taint `workload=edge:NoSchedule` |
| Floating IP | assigned here in the last move step |
| Terraform lifecycle | `ignore_changes = [image]` only |

## Workload placement

Which pods are pinned to the edge node. Rows are in the order they move.

| Order | Workload | Mechanism |
|---|---|---|
| 1 | CoreDNS copy | a second Deployment with the `kube-dns` label, pinned |
| 2 | Valkey | `nodeSelector` and toleration |
| 3 | Postgres cluster | a second instance by replication, then switchover |
| 4 | Synapse main, MAS, haproxy, auth service, element-web, `rtc-transports-stub` | `nodeSelector` and toleration |
| 5 | SFU, `sfu-tls-proxy`, `sfu-proxy` | `nodeSelector` and toleration, kept together |
| 6 | Envoy data plane | the `EnvoyProxy` resource's node selector and toleration |
| 7 | Floating IP | Terraform assignment, plus the edge binding unit |

All edge workloads carry tolerations of 900 seconds for `node.kubernetes.io/unreachable` and
`not-ready`.

## Generation (one NixOS system version on a machine)

| Field | Meaning |
|---|---|
| `generation` | the profile number on the machine |
| `store_path` | the system closure |
| `boot_entry` | its GRUB menu entry title |
| `state` | `previous`, `current`, `trial` or `permanent` |

## Patch run

One execution of the procedure on one machine. The fields are the record the operator keeps, in
UTC (spec FR-010).

| Field | Meaning |
|---|---|
| `machine` | master or edge |
| `started_at`, `ended_at` | ISO 8601 UTC |
| `gates` | each pre-check, its result and detail |
| `snapshot` | the pre-patch server snapshot, if taken |
| `from_generation`, `to_generation` | before and after |
| `servers_created`, `servers_deleted` | must both be 0 (spec FR-004) |
| `restart_counts_before`, `restart_counts_after` | for edge pods, compared at the end |
| `unlock` | for the master: when the prompt was answered and by whom (never the passphrase) |
| `mode` | `normal` or `first-patch` |
| `unlock_path` | for the master: `edge` (jump host) or `public` |
| `outcome` | `completed`, `aborted` with the reason, or `rolled-back` with the layer used |

## State machine: one machine's patch

```text
idle ──(gates pass)──> staged ──(deploy --boot + grub-reboot)──> trial-set
trial-set ──(reboot, unlock for the master)──> trial-running
trial-running ──(health checks pass)──> confirmed ──(grub-set-default)──> permanent
trial-running ──(health fails or no SSH in time)──> hung ──(hard reset)──> previous-running
staged / trial-set ──(abort before reboot)──> idle
```

- `staged`: the new generation is installed and the boot entry exists. Nothing has rebooted.
- `trial-set`: GRUB is told to use the new entry once.
- `trial-running`: the machine runs the new generation, with the old one still the saved default.
- `confirmed` and `permanent`: the new generation is the saved default. Only now is the patch done.
- `hung`: no healthy answer within the limit. A hard reset boots the previous generation by itself.
- `previous-running`: the machine is back on the old version, and the run is recorded as
  `rolled-back`.

The new generation is never the default until `confirmed`. That is the fallback rule (spec FR-008).

## Validation rules (from the requirements)

- A routine patch never creates or deletes a server (FR-004).
- The call machine's patch refuses while the SFU reports any participant, and re-checks immediately
  before the reboot (FR-005, FR-006).
- Any failed gate aborts before anything changes (FR-007).
- A control-plane reboot happens only with the owner's approval and passphrase for that run.
