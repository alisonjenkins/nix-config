# Migration run records

One section per volume. Times are UTC.

## `couchdb-data` -> `couchdb-data-enc` (T073, 2026-10-04)

| Step | Result |
|---|---|
| New claim `couchdb-data-enc` on `hcloud-volumes-encrypted` (home-cluster#1572) | merged, `Pending` (WaitForFirstConsumer) until the copy job mounted it |
| Pause GitOps (`flux suspend kustomization flux-system`), `couchdb` scaled to 0 | about 14:08Z; the pod was gone before the copy |
| `migrate-files.sh --execute --uid 5984 --gid 5984` | first run **failed**: a non-root `rsync -a` cannot set times on the claim root or on the root-owned `lost+found` (exit 23), and the script refused as designed. Fixed in nix-config#479 (`--omit-dir-times --exclude=/lost+found`); second run copied 10 files at 14:12:08Z |
| Manifests (path, size, sha256, owner) of both claims | **identical**, 10 files each, owner `5984:5984` throughout |
| Old PV `pvc-fe5eb7e8…` set to `Retain` (`retain-pv.sh`) | done before the switch |
| Switch (home-cluster#1573: Deployment mounts `couchdb-data-enc`, plain claim removed), Flux resumed | applied at about 14:13Z; downtime about 5 minutes |
| Health | new pod `Running` and ready on the encrypted claim |
| Functional | all four databases listed; `obsidianlivesync` holds 3,068 documents; a test database was created, a document written and read back, and the database deleted |
| Fresh backup `couchdb-enc-20261004t141409z` | `Completed`, no errors or warnings, 14:14:54Z |

One surprise: when Flux resumed, an old-template pod briefly started on the old claim (about 3 s before the new one) and was
terminated by the rollout. The data had already been copied and the old claim was no longer used afterwards.

**Encryption verdict (2026-10-04T15:11:58Z, after the owner allowed root access):** `verify.sh --checks encryption` through a debug
pod on the master: `crypto_LUKS` on the raw device, mapping active, passphrase Secret set, `verdict=verified` (new volume
`pvc-1a920b1e…`, Hetzner id 107030571). The old volume (Hetzner id 106201840, PV `pvc-fe5eb7e8…`, `Released`, `Retain`) is untouched
and is the way back; its removal is still open (see "Old volumes" below).
The 24 hour limit of SC-007 runs from the switch (about 14:13Z): run the node check and destroy the old volume before then.

## `ntfy-data` -> `ntfy-data-enc` (T074, 2026-10-04)

Same sequence as couchdb (new claim merged first, Flux paused, service to 0, `migrate-files.sh --uid 1000 --gid 1000`, old PV `Retain`, switch merged, Flux resumed).

| Step | Result |
|---|---|
| Copy | 14:27:27Z, 2 files, manifests (path, size, sha256, owner `1000:1000`) **identical** |
| Switch (home-cluster#1575) | `ntfy` rolled out on `ntfy-data-enc`; downtime about 4 minutes |
| Mount seen inside the pod | `/dev/mapper/scsi-0HC_Volume_107030635` (device-mapper, the encrypted-volume signature seen in T024) |
| Functional | `/v1/health` healthy; users `ali` and `alertmanager` present; a test message published with the alertmanager token to its topic and read back with the admin user |
| Fresh backup `ntfy-enc-20261004t142839z` | `Completed`, no errors |

The old volume (Hetzner id 106190223, PV `pvc-e280df3f…`) is `Released` and `Retain`. Same open item as couchdb: no node-level encryption verdict yet, so it is not destroyed.

## Grafana `kube-prometheus-stack-grafana` -> `grafana-data-enc` (T075, 2026-10-04)

| Step | Result |
|---|---|
| New claim `grafana-data-enc` (home-cluster#1576), copy with `--uid 472 --gid 472` | 14:31:09Z, 598 files, manifests **identical**, owner `472:472` |
| Switch (home-cluster#1577: chart `persistence.existingClaim`) | the chart's own claim was removed on upgrade; its PV `pvc-36ef7538…` (Hetzner id 106169150) is `Released` and `Retain` |
| Functional | woke Grafana through Elasti with an in-cluster request; the pod mounts `grafana-data-enc`; `/api/health` reports `database: ok`, and the log shows `migrations completed performed=0 skipped=719` (the existing database was read, not recreated). Datasources and dashboards were not listed: basic auth is off for the API and the gateway login is behind a hashed credential |
| Encryption verdict | `verdict=verified` at 15:13:21Z (volume 107030644). A first run at 15:12:04Z said `failed` ("fstype none, cannot read raw device") only because Elasti had scaled Grafana to 0, so the volume was not attached to the node; with Grafana woken it passed |
| Backup | first on-demand `monitoring` backup `PartiallyFailed` (Elasti scaled Grafana away mid-backup, "error to expose PVB … pod not found"; the Prometheus and Alertmanager volumes in it were fine); repeated with Grafana awake: `monitoring-enc-20261004t151335z` `Completed`, no errors, 15:15:37Z |

## Prometheus and Alertmanager (T075, T076, 2026-10-04)

Both are operator-managed StatefulSets with an immutable `volumeClaimTemplate`, so the claims were swapped by hand. A first attempt was
stopped by the session's permission guard before it changed anything (monitoring was paused for a few minutes and restored); the
owner then allowed it and it ran:

1. Flux root Kustomization and the `kube-prometheus-stack` HelmRelease suspended; both custom resources patched to `replicas: 0`
   (15:06:32Z); the StatefulSets reached 0.
2. For each: a temporary encrypted claim, `migrate-files.sh --uid 1000 --gid 2000` from the old claim, manifests compared, both PVs
   set to `Retain`, the temporary claim deleted, the old claim deleted, a new claim with the **original name** created pointing at
   the encrypted volume (`volumeName`), and that volume's reclaim policy set back to `Delete` (the class default).
3. Copy results: Alertmanager 2 files at 15:07:25Z and Prometheus 68 files at 15:09:08Z, manifests **identical** (owner `1000:2000`).
4. home-cluster#1578 merged (class `hcloud-volumes-encrypted` in both `volumeClaimTemplate`s), Flux and the HelmRelease resumed; Helm
   reset `replicas` to 1 and the operator recreated both StatefulSets on the swapped claims. Both pods `Ready` about 5 minutes after
   the stop.
5. Functional: a range query of `count(up)` over the last hour returns samples continuously across the stop (history kept; the
   5 minute staleness window covers the gap); Alertmanager still lists its 1 silence.
6. Encryption verdicts at 15:12:06Z (Alertmanager, volume 107030839) and 15:12:08Z (Prometheus, 107030844): `verified`.
7. Backup: Prometheus and Alertmanager volumes `Completed` in `monitoring-enc-20261004t151335z`.

The old volumes are `Released` and `Retain`: Alertmanager PV `pvc-26c7ac91…` (Hetzner id 106169151), Prometheus PV
`pvc-cb801167…` (106169152). Their old claim names now belong to the new volumes, so `destroy-old-volume.sh` must NOT be used for
these two (it would delete the new claim): delete only the old PV object and its Hetzner volume.

## Removal log (T060, T078)

All five migrated volumes had a `verified` encryption verdict after their switch (verdict files in
`~/hetzner-encrypted-volumes/verdicts/`) and a completed backup, and every old PV was `Released` and `Retain`. The session's
permission guard first denied the cloud volume delete; the owner then gave the go-ahead ("yes delete the old volumes") and the
volumes were removed. Couchdb, ntfy and Grafana went through `destroy-old-volume.sh --execute` (all gates passed). Alertmanager
and Prometheus did not: their old claim names now belong to the new volumes, so the script (which deletes the claim) would have
destroyed the new claim. For those two only the old PV object and its Hetzner volume were deleted, after checking that the PV was
`Released`, its volume handle matched the Hetzner id, the Hetzner volume's name equalled the PV name, and it was not attached to a server.

| Old volume | Hetzner id | PV | Switch (UTC) | Removed (UTC) | Within 24 h |
|---|---|---|---|---|---|
| couchdb-data | 106201840 | `pvc-fe5eb7e8…` | about 14:13Z | 15:20:24Z | yes |
| ntfy-data | 106190223 | `pvc-e280df3f…` | about 14:28Z | 15:20:27Z | yes |
| Grafana | 106169150 | `pvc-36ef7538…` | about 14:38Z | 15:20:28Z | yes |
| Alertmanager | 106169151 | `pvc-26c7ac91…` | about 15:07Z | 15:20:50Z | yes |
| Prometheus | 106169152 | `pvc-cb801167…` | about 15:09Z | 15:20:51Z | yes |

After the removals `hcloud volume list` shows the five encrypted volumes, the master state disk and four plain data volumes
that are still to move: `ente-db` (`pvc-c2e48d50…`), Synapse media (`pvc-27565201…`), `shared-postgres` (`pvc-5e189937…`) and the
Minecraft world (`pvc-22ab50ca…`).

## Synapse media `matrix-stack-synapse-media` -> `matrix-stack-synapse-media-enc` (T062 to T066, 2026-10-04)

Done at the owner's request ("do the matrix stuff now quickly"), on a Sunday, with `check-no-call.sh` printing `calls=0`.

| Step | Result |
|---|---|
| Chart value | `synapse.media.storage.existingClaim` (the chart's own claim carries `helm.sh/resource-policy: keep`); new claim `matrix-stack-synapse-media-enc` merged first (home-cluster#1580) |
| Backup before the move | `matrix-enc-pre-20261004t163156z` `Completed`, no errors (media 858,760,764 bytes; the `pgdata` exclusion was already in place) |
| Stop | 16:34:54Z: `matrix` Flux Kustomization and the `matrix-stack` HelmRelease (in namespace `matrix`) suspended, `matrix-stack-synapse-main` scaled to 0 |
| Copy | `migrate-files.sh --uid 10091 --gid 10091`: 890 files, finished 16:36:31Z, manifests **identical** (owner `10091:10091`) |
| Old PV | `Retain` before the switch |
| Switch (home-cluster#1581) and resume | Synapse back on the encrypted claim at about 16:40Z; Synapse was down about **5 minutes** (the chart upgrade and pod start dominated; the copy took 1.5 minutes) |
| Mount in the pod | `/dev/mapper/scsi-0HC_Volume_107031334` |
| Health | all Matrix pods Running, client API 200 from outside, the SFU and its auth service Running (`lk_jwt_service` health checks passing); rooms that were in a call closed on idle timeout when the database restarted at 16:18Z, earlier. User `@lace` was syncing from Element X and a browser throughout |
| Encryption verdict | `verdict=verified` at 16:40:36Z (volume 107031334) |

### Restore test of the media backup (T046)

Backup `matrix-media-staging-20261004t172840z`: a read-write staging pod mounting the claim (a read-only second mount of a volume already
mounted read-write by Synapse fails: `mount -o ro` on the same device) selected by label, with `persistentvolumes`, `Completed`, no errors, 858,760,764 bytes.
Restore `restore-test-matrix-d172914` into namespace `restore-test-matrix`: the data restore `Completed` (858,760,764 of 858,760,764 bytes),
the scratch claim bound to **its own new encrypted volume** (`check-restored-pvcs.sh` passed), and one expected error: Velero also
restored the Synapse pod because it mounts the selected claim, and that pod could not be created in the scratch namespace (its
service account does not exist there), so no second Synapse started. Comparison: the restored volume's manifest (path, size, sha256,
owner) is **identical** to the live one for all 890 files; the only extra file is Velero's own `.velero/<id>` marker.

Things that did not work, for the next restore test of a pod with many init containers: patching the restored Synapse pod's
`initContainers` through a resource modifier (Velero's `restore-wait` init container and the chart's own both mount volumes that the
patch removed, so pod creation failed three times), and restoring a pod that is not the staging pod. Restore a staging pod instead.
A resource modifier's `value` must be a JSON **string**, not YAML. A restore that is deleted while `InProgress` keeps its finalizers and
blocks every later restore until they are removed by hand (the later restore stays without a phase).

Cleaned up: the scratch namespace and its volume, the Restore objects, the modifier ConfigMap and the staging pod.

### Removal and schedule

The old plain media volume (Hetzner id 106859394, PV `pvc-27565201…`) was removed with `destroy-old-volume.sh --execute` at
**17:32:30Z**, within 24 hours of the switch (all gates passed: verified verdict after the switch, a completed backup after it, `Retain`,
no pod mounting the claim). The daily `matrix` Velero schedule is enabled (home-cluster#1582, `0 4 * * *`).

## `ente-db-1` -> `ente-db-2` on the encrypted class (T050 to T052, T072, T078 for ente-db, 2026-10-04)

Done at the owner's request on a Sunday evening (no call gate: the photo service does not use the SFU).

### Rehearsal on a scratch cluster (T050, T051)

A one-instance `Cluster` `rehearsal` (namespace `scratch-migrate`, 10 Gi on `hcloud-volumes`, 50,000 test rows) was changed to
`hcloud-volumes-encrypted` and scaled to 2:

| Question | Answer |
|---|---|
| Does the webhook accept a changed `storage.storageClass` on an existing cluster? | **yes**; the existing instance keeps its plain claim, the new one is created on the encrypted class (`rehearsal-2` on `hcloud-volumes-encrypted`) |
| Replica build | ready in about 31 s, streaming, rows identical (count and md5 of all values) |
| `kubectl cnpg promote` interruption | about **35 s** of failed queries through `rehearsal-rw` with idle clients (1.5 s probe interval); data intact, the old instance became a replica |
| `kubectl cnpg destroy rehearsal-1` | the operator **recreates the instance while `instances` is still 2**, so lower `instances` in the same step; the destroyed instance's volume has reclaim policy `Delete` (it went `Released` and would be removed): set `Retain` first |
| Way back | not rehearsed (the old instance stays until the new one is verified, so it is a promote away) |

**T051: the primary method (replica on the encrypted class, switchover) is confirmed; no replica-cluster fallback needed.** The
scratch namespace, its volumes and PVs were deleted (0 PVs and 0 Hetzner volumes left).

### The migration (home-cluster#1585, #1586, #1587)

| Step | Result |
|---|---|
| Class for new volumes (#1585) | `storage.storageClass: hcloud-volumes-encrypted`; `ente-db-1` untouched |
| Second instance (#1586) | `instances: 2`, plus `smartShutdownTimeout: 10` (the 180 s default kept new connections refused for 3 minutes on the earlier restarts; the setting did not restart the primary). `ente-db-2` Ready on `hcloud-volumes-encrypted` about 1 minute after the reconcile, streaming, 0 bytes lag |
| Before the switch | fresh encrypted dump (33 MB, end marker checked, 21:13:25Z), plugin base backup `ente-db-pre-switch-20261004t211327` `completed`; encryption verdict for the replica volume `verified` at 21:13:54Z (Hetzner volume 107032753) |
| Switchover | `kubectl cnpg promote ente-db ente-db-2` at 21:14:07Z; Museum's public `/ping` (needs the database) failed for **8 seconds** (14 failed probes of 61, from 1.3 s to 9.3 s after the promote) |
| After | `ente-db-2` primary and `Cluster in healthy state`; `ente-db-1` demoted to a replica (its container restarted once, expected) |
| Verification (21:15:42Z and 21:16:14Z) | encryption `pass` (`crypto_LUKS`, mapping active, Secret set); database compare `pass` (`ente`: 81 tables, row counts and checksums identical old against new; `postgres`: 0 tables); backup `pass` (`ente-db-post-switch-20261004t211517` `completed` after the switch); Museum `/ping` 200, its error lines were the switchover blip only; `verdict=verified` for these three checks |
| Health check | `verify.sh --checks health` **failed on a false positive**: its log pattern matches the JSON field name `error_severity` and the words "database system" in CloudNativePG's structured start-up lines (all `LOG`, plus `FATAL 57P03 the database system is starting up` during the replica's normal start). The new primary was checked by hand instead (Ready, 0 restarts, Museum 200). A fix with tests is in progress (branch `fix/verify-health-json-logs`) |
| Retain and remove the old instance (#1587) | `ente-db-1` PV `pvc-c2e48d50…` set to `Retain`, `instances` back to 1, the operator removed `ente-db-1` |
| Old volume removed | `destroy-old-volume.sh --execute` at **21:18:30Z** (Hetzner id 106169213), 4 minutes after the switch |

The functional check for the photo service (sign in, open a known album) was not exercised: it needs credentials the session does not have.
Left to do for the old archive: the restore test of the new plugin chain (T033), then removing the old Hetzner Object Storage bucket.
