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

## Old volumes: removal is open

All five migrated volumes have a `verified` encryption verdict after their switch (verdict files in
`~/hetzner-encrypted-volumes/verdicts/`) and a completed backup, and every old PV is `Released` and `Retain`. Dry runs of
`destroy-old-volume.sh` for couchdb, ntfy and Grafana pass every gate. The deletion of the five old Hetzner volumes was denied by the
session's permission guard (it is a cloud volume delete), so they remain, as the way back. SC-007's 24 hour limit runs from each
switch (couchdb about 14:13Z, ntfy 14:28Z, Grafana about 14:38Z, Alertmanager 15:07Z, Prometheus 15:09Z): they need the owner's go-ahead,
or the owner can delete them.

| Old volume | Hetzner id | PV |
|---|---|---|
| couchdb-data | 106201840 | `pvc-fe5eb7e8…` |
| ntfy-data | 106190223 | `pvc-e280df3f…` |
| Grafana | 106169150 | `pvc-36ef7538…` |
| Alertmanager | 106169151 | `pvc-26c7ac91…` |
| Prometheus | 106169152 | `pvc-cb801167…` |
