# Master memory budget (T021)

Measured 2026-10-03T18:34Z on `hetzner-k8s-master-1`, read-only (`kubectl top`, `kubectl describe node`, Prometheus
`node-exporter` for instance `10.0.1.10:9100`). The master is the only node in the cluster.

**The master cannot take all the new load at once.** Free memory now is about 1.5 GiB, and the new components together
are expected to use about 1.2 GiB, up to 3.4 GiB if every one reaches its limit. So the work is staged, with a stop
threshold and a no-overlap rule, below.

## Now

| Measure | Value |
|---|---|
| Total memory | 7747 MiB |
| In use by the node (`kubectl top node`) | 5689 MiB (73%) |
| `MemAvailable` | 1553 MiB (80% used by this measure) |
| Pod memory, sum of `kubectl top pods -A` | 3574 MiB |
| Used by everything that is not a pod (kernel, k3s, containerd, cache) | about 2.1 GiB |
| Swap in use | 344 MiB of 7747 MiB (no zram, so it is a swap device or file) |
| Requests / limits allocated to pods | 4852 MiB (62%) / 27856 MiB (359%) |

Last 7 days: `MemAvailable` fell to **909 MiB** at its lowest, memory in use peaked at **88.0%**, swap in use peaked at
**406 MiB**, swap-in reached **308 pages per second**, and there were **0 OOM kills**. The limits are heavily
overcommitted, so the node is only safe while real use stays low.

Largest pods now: Prometheus 617 MiB, Cilium 196 MiB, `shared-postgres-1` 177 MiB, Tetragon 164 MiB, Synapse 143 MiB,
`ente-db-1` 100 MiB.

## Added load

"Expected" is my estimate, not a measurement. Only the Postgres instances have a measured baseline (the existing
instances' current use). T044 measures the Velero node-agent on a real 10 GiB volume and replaces its row.

| Component | Request | Limit | Expected use | Notes |
|---|---|---|---|---|
| Second `shared-postgres` instance | 512 MiB | 1 GiB | 200 to 400 MiB | Exists only during a migration |
| Second `ente-db` instance | 256 MiB | 512 MiB | 100 to 200 MiB | Exists only during a migration |
| Barman plugin sidecars (2 clusters) and controller | 32 MiB each | 128 MiB each | 100 to 250 MiB | New, unmeasured |
| Velero server | 128 MiB | 512 MiB | 100 to 200 MiB | New |
| Velero node-agent (Kopia) | 256 MiB | 1 GiB | 300 to 800 MiB | Grows with the volume being backed up |
| **Total** | | **about 3.4 GiB** | **about 0.8 to 1.9 GiB** | |

Against 1553 MiB available now, and 909 MiB at the 7 day low, the expected total uses most or all of the headroom. The
node would push into swap. Swap has 7.4 GiB free, but swapping on this node is what the 2026-09-29 slowdown looked like.

## Stop threshold

Stop the step and back it out if **any** of these holds on the master:

1. `MemAvailable` below **700 MiB**. That is below the 7 day low of 909 MiB, so it is not hit by normal load.
2. Swap in use above **1 GiB**. That is about 2.5 times the 7 day peak.
3. Swap-in above **1000 pages per second** for 5 minutes.
4. Any increase in `node_vmstat_oom_kill`.
5. A restart of k3s, Cilium or CoreDNS.

Check it before each memory-adding step and during the first backup of each kind, with `kubectl top node` and, for the
rest, Prometheus on the node-exporter series for `10.0.1.10:9100`.

## No-overlap rule

At most one of these runs at a time:

- a second database instance existing for a migration (T050 onward, from the instance's start to its removal);
- a Velero backup or restore running;
- a database base backup running.

In practice: schedule Velero's daily backups outside any migration window (T040's stagger), and do not start a
migration while a backup is running. The first full backup of each file volume (T046, T047) runs on its own. A
migration or backup that would overlap another waits.

## Settings

- Keep the limits in the table. Set every request shown, so the scheduler accounts for them and the sums above are real.
- The node-agent keeps its 1 GiB limit (Kopia needs it for a large volume). If T044 shows it reaching the limit, lower
  Kopia's parallelism before raising the limit.
- If a step breaks the threshold, the levers in order: wait for another job to finish, lower Kopia parallelism, then ask
  the owner. Stopping unrelated workloads is the owner's decision, not part of this procedure.

## Longer term

The master is also the only place any of this runs. The call stack moving to its own node (spec 003) would take Synapse,
its database and the SFU off it and make this budget much easier.
