# 0026. Keep Hetzner worker nodes usable: dial kubelets by name, heal a stuck Cilium host datapath

- Status: Accepted
- Date: 2026-10-05

## Context

Starting the Minecraft server on a fresh Karpenter game node exposed two separate faults that both
looked like "the node is broken". Neither is.

**1. The API server could not reach a worker's kubelet.** `kubectl logs`, `exec`, `debug`, port-forward
and Velero's exec hooks to a pod on a worker failed with
`x509: certificate is valid for 127.0.0.1, ::1, <public ip>, not 10.0.1.1`. Workers join k3s with
`--node-ip` set to their public address (the hcloud CCM rejects a private one), and k3s signs the agent's
kubelet certificate from that alone. The CCM then adds the private `InternalIP`, and k3s makes the API
server dial `InternalIP` first. The master's certificate covers its private IP, so the same paths work
there. Velero's pre-hook is `on-error: Fail`, so the world backups ended `PartiallyFailed`.

**2. One in three new nodes had a dead host datapath.** Cilium dropped every host to pod packet with
`drop (Host datapath not ready)`. Kubelet probes timed out, Cilium's own health endpoint failed, and the
hcloud CSI node driver was killed by its liveness probe, then backed off to `CrashLoopBackOff`
(up to 5 minutes), so volumes could not be mounted: a Minecraft start took 15 minutes instead of 3.
The cause is upstream, cilium/cilium#42907 (open): with the host firewall on, `bpf_lxc` sends every
host to pod packet through the host endpoint's policy program, found by a host endpoint ID compiled into
each program. If the agent initializes the datapath before the host endpoint exists, a wrong default ID
is baked in, the tail call finds nothing, and the node stays dropped until the agent restarts. Cilium
1.19.5 is affected and 1.19.8 and 1.20.2 contain the same tail call, so upgrading is not a fix.

How it was found: `cilium-dbg monitor --type drop` on a failing node named the drop reason; the Cilium
source at the running tag showed which condition produces it; Prometheus history of nine game nodes
showed CSI restarts of 0, 0, 0, 0, 0, 13, 2, 4, 2 (an intermittent fault, not a bad node, and not the
image: identical kernel and OS on all nine); restarting the agent on the stuck node cleared the drops
at once; the upstream issue described the same signature.

## Decision

- **Dial kubelets by node name.** The k3s server runs
  `--kube-apiserver-arg=kubelet-preferred-address-types=Hostname,InternalIP,ExternalIP`
  (`lib/hetzner-node-services.nix`). Both the worker and the master certificates carry the node name,
  and the k3s tunnel server maps a node-name dial to that node. `ExternalIP` first would break the
  master (its certificate lacks its public IP). A live `config.yaml.d` file applied the same setting to
  the running master (runbook in `docs/hetzner-k3s-live-maintenance.md`) until the next replacement.
- **Give the CSI node driver a startup probe** (`node.customStartupProbe` in the `hcloud-csi`
  HelmRelease, 5 s period, 60 failures) so a slow datapath cannot kill a healthy driver.
- **Run a watchdog that restarts a stuck agent** (`cilium-hostfw-watchdog` DaemonSet, home-cluster). In the
  cluster's own Cilium image with `hostPID` and `CAP_KILL` only (no API token), it watches the cumulative
  `Host datapath not ready` drop counter's change and, when it has risen for 90 s on an agent at least
  180 s old (a normal start finishes within about 90 s), kills the agent process so the kubelet restarts it.
  Cooldown 10 minutes, and only when exactly one `cilium-agent` is visible.

## Alternatives rejected

- **Prefer `ExternalIP` for kubelet dials.** Breaks exec and logs on the master.
- **A private `--node-ip` on workers.** The hcloud CCM rejects it and never sets the provider ID.
- **Upgrade Cilium.** The same tail call is in 1.19.8 and 1.20.2 and the upstream issue is open.
- **Turn the host firewall off.** It enforces the control-plane host policy; removing a security control to
  avoid a startup race is the owner's call, not a side effect.
- **`hostNetwork: true` for the CSI node pod.** It avoids the pod datapath, but changes the driver's
  network surface cluster-wide for a problem the startup probe already removes.
- **Delete the Cilium pod through the API.** Needs a token and RBAC to delete `kube-system` pods, and the
  official kubectl image has no shell. Signalling the agent process needs less.
- **Treat it as a bad node and recycle it.** One in three new nodes is affected and the replacement can
  be stuck too.

## Consequences

- A stuck node now heals itself about 3 to 4 minutes after it joins, instead of staying broken. Until
  then the CSI driver stays up and waits, so a pod that needs a volume starts after the heal, not never.
- `kubectl logs/exec` and Velero exec hooks reach worker pods, so the Minecraft world backups
  (`on-error: Fail`) work.
- The watchdog's threshold (90 s of rising drops, agent at least 180 s old) is a judgement from one
  measured worst case (88 s of regeneration); if a legitimate start ever needs longer it will restart a
  healthy agent once, and the cooldown stops it from looping.
- The flag and the watchdog are workarounds. Both can go when the upstream bug is fixed.

## Evidence

2026-10-05: a Velero backup of the running world through the hooks completed in 69 s and the world
restored from it read 178,391 chunks with none unreadable (`specs/004-hetzner-encrypted-volumes/
evidence/backups.md`). Three fresh game nodes with the watchdog running: two never triggered it; the third
(`game-hvdj8`) was restarted at agent age 184 s, the drop counter stopped rising (488), and the CSI driver
ended 3/3 with 0 restarts. Earlier fresh nodes: `game-vjw6j` 13 CSI restarts and still dropping after
minutes, `game-78rvf` 4, `game-b8lxg` 2, `game-gz7bc` 2 then stuck again after a rollout until the agent
was restarted.

## Revisit when

- cilium/cilium#42907 is fixed in a release we run: remove the watchdog and keep or drop the startup probe.
- The master image is replaced: check that the server unit carries the kubelet address types and that the live
  `config.yaml.d` file is gone.
- The hcloud CCM accepts a private `--node-ip`: workers could use it and the address-type flag becomes unnecessary.
