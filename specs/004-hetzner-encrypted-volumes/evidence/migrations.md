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

**Open: the encryption verdict.** `verify.sh --checks encryption` needs read-only commands on the node (a root debug pod). The
attempt to create one was denied by the session's permission guard, so the check has not been run on the new volume
(`pvc-1a920b1e…`, Hetzner volume 107030571). Until it passes, `destroy-old-volume.sh` will not remove the old volume (it needs a
`verified` verdict). The old volume (Hetzner id 106201840, PV `pvc-fe5eb7e8…`, `Released`, `Retain`) is untouched and is the way back.
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
| Backup | covered by the daily `monitoring` schedule; no on-demand backup was taken |

## Prometheus and Alertmanager (T075, T076): not migrated

Both are operator-managed StatefulSets with an immutable `volumeClaimTemplate`. The plan was to stop both through their custom resources with Flux paused, copy each claim to a temporary encrypted claim, then rebind that volume to the original claim name (`Retain` on both PVs), and finally change the class in the HelmRelease values (home-cluster#1578, held as a draft). The session's permission guard denied the claim swap (it deletes and recreates claims on the live monitoring stack), so it was not run. Monitoring was stopped for a few minutes during the attempt (the time was not recorded) and restored: both StatefulSets are back at 1/1 and Flux is resumed. Nothing was copied or deleted. **Do not merge home-cluster#1578 before the swap**: the operator would try to recreate the StatefulSets with a new class under the existing plain claims.
