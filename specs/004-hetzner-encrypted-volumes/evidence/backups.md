# Backup evidence (Phase 3)

## T028: the Barman Cloud Plugin is installed (2026-10-04T05:55Z)

home-cluster PR 1564 merged: upstream release v0.15.1 (unmodified manifest, sha256 recorded in its `kustomization.yaml`), its own Flux
Kustomization `cnpg-barman-plugin`. Afterwards: the Kustomization is Ready, the `barman-cloud` pod is Running (11 MiB used, limit 128 MiB),
both Certificates are Ready, the `objectstores.barmancloud.cnpg.io` CRD exists, and the operator logged `Registered plugin` (after a few
transient errors while its TLS Secret was being issued). Master memory stayed at 75% and both Postgres clusters stayed healthy.

The plugin's upstream ClusterRole can read every Secret and create Roles and RoleBindings. The CloudNativePG operator already holds
comparable access, so it does not widen who can read the volume passphrase; recorded here and in the PR.

## What the databases had before this work (read-only, 2026-10-04)

- `ente-db`: a working in-tree backup. Daily base backups since 2026-09-04 (first recoverability point `2026-09-04T03:00:18Z`, latest
  `2026-10-04T03:00:13Z`), continuous archiving working, 30 day retention, a Hetzner Object Storage bucket, static `ente-s3` key. Two
  older backups failed (2026-07-13, 2026-07-30) before the current run of successes. ADR 0022 had said it had none; corrected.
- `shared-postgres`: no backup (no backup section, no recoverability point, no `Backup` objects).

## T034: encrypted safety dumps (2026-10-04T05:56Z)

`pg_dumpall` of each cluster, streamed through `age` to the owner's age key (`admin_ali` in `.sops.yaml`) into
`~/hetzner-encrypted-volumes/dumps/` (directory mode 700, files mode 600). The plaintext existed only in the pipe. Each file was
decrypted and counted without printing: it ends with the "PostgreSQL database cluster dump complete" marker and has the expected
databases.

| Cluster | File | Size | Databases | Complete marker | SHA-256 (first 16) |
|---|---|---|---|---|---|
| `shared-postgres` | `20261004T055645Z-shared-postgres.sql.age` | 138,199,677 bytes | 4 | yes | `e605c20fb23bc893` |
| `ente-db` | `20261004T055645Z-ente-db.sql.age` | 33,296,030 bytes | 1 | yes | `b85dee486ffc4327` |

These are deleted at the end of the migrations (T061).

## Probe of the new role before any database used it (2026-10-04T05:59Z to 06:03Z)

A scratch pod in `matrix` (ServiceAccount `shared-postgres`, `AWS_ROLE_ARN` set to `hetzner-cnpg-backup-shared-postgres-irsa`, a projected
`sts.amazonaws.com` token whose claims were `iss=…/hetzner-k8s-irsa`, `sub=system:serviceaccount:matrix:shared-postgres`) ran the real
`barman-cloud` tools and a boto3 matrix against `s3://ajj-backups/cnpg-hetzner/shared-postgres`:

| Operation | Result |
|---|---|
| `barman-cloud-check-wal-archive` | **failed: `HeadBucket … 403 Forbidden`** |
| `barman-cloud-backup-list` | works (empty list) |
| `HeadBucket` | **denied (should work)** |
| `ListMultipartUploads`, with or without the prefix | **denied (should work)** |
| `GetBucketLocation`, list under own prefix, put, get, delete under own prefix | work |
| `CreateMultipartUpload`, `ListParts`, `UploadPart`, `AbortMultipartUpload` | work |
| list at the bucket root, list or put or get under `cnpg/` or `velero-hetzner/` | denied, as intended |

Both failures are in the policy applied under T005 to T008 and would have made WAL archiving fail on the live database. The fix is T008a
(Terraform commit `ad39500`, awaiting the owner's `tofu apply`). The scratch pod was deleted; the probe left one incomplete multipart
upload (`cnpg-hetzner/shared-postgres/_iam-probe/mpu.bin`) to abort once the role may list uploads.

## T013, T038 to T041: Velero installed and a first backup works (2026-10-04T06:08Z to 06:18Z)

home-cluster PR 1566 merged (namespace, repository password Secret, HelmRelease: chart 12.2.0, Velero 1.18.2, plugin v1.14.4, Kopia, web
identity `hetzner-velero-irsa`, no stored key). The repository password was generated from `/dev/urandom` and never printed; its
64 character value decrypts with the owner's key. **A copy in the password manager is still to do (owner):** losing it makes every
backup unreadable.

Flux installed it in 57 s. The storage location reported `Available` (validated against `s3://ajj-backups/velero-hetzner`), so Velero's
own listing calls work with the role as applied. Node memory went from 76% to 79% (about 230 MiB), above the 75% of T021's baseline but
well clear of the stop threshold (available memory under 700 MiB).

### The first backup failed, and why

A backup of namespace `ntfy` ended `PartiallyFailed`: all three Kopia volume backups failed with
`error to expose PVB: error to create hosting pod: admission webhook "validate.kyverno.svc-fail" denied the request … require-resource-limits`.
Velero 1.18 starts a temporary hosting pod per volume backup, with no resources, and this cluster's Kyverno policy requires limits on every
container in a workload namespace. These pods exist only at run time, so `helm template` of the chart could not show it. Fixed by PR 1567:
a `velero-node-agent-config` ConfigMap with `podResources` (`50m`/`500m` CPU, `128Mi`/`512Mi` memory) and `loadConcurrency: 1`, read through
`--node-agent-configmap`. The failed backup was removed with a `DeleteBackupRequest`.

### After the fix

Backup `second-ntfy-20261004` (started 06:17:08Z): `Completed`, 46 of 46 items, no errors or warnings, and all three volume backups
completed (`data`, `tmp`, `rendered-config`).

## T046 (part): restore test of `ntfy-data` (2026-10-04T06:19Z)

`Restore` of that backup with `namespaceMapping ntfy -> restore-test-ntfy`, excluding the hostname route (so the scratch copy cannot claim a
live hostname), policy reports and endpoints: `Completed`, 3 volume restores completed, restored pods Running, 5 warnings that are all benign
(CRDs, `kube-root-ca.crt` and a CiliumEndpoint already exist).

| File in `/var/lib/ntfy` | Live | Restored | Result |
|---|---|---|---|
| `cache.db` | 348160 bytes, sha `7b796bc05b1c72cc…` | same | byte-identical |
| `user.db` | 118784 bytes, sha `72acab57dacca494…` | 118784 bytes, sha `c45ded9455c29f4c…` | bytes differ, content identical |

`user.db` had not changed on the live volume since before the backup (mtime Oct 3 10:23), yet the restored copy differs. Comparing the logical
contents settled it: `PRAGMA integrity_check` is `ok` on both, the schemas match (8 tables), and `sqlite3 .dump | sha256sum` is `84c58fe9375a8316`
for both. The restored ntfy had been running for 2 minutes, and SQLite rewrites header fields when a database is opened. Velero also adds a
`.velero/<uid>` marker file to a restored volume, which is not data. Lessons for the remaining restore tests: compare files while the
restored workload is not running when the format is a database, or compare logical contents; ignore `.velero/`. My local copies of the
databases (they hold ntfy user records) were shredded, and the scratch namespace, its volume and the restore object were deleted.

T046 stays open for `couchdb-data`, `matrix-stack-synapse-media`, the Alertmanager and Prometheus volumes. Restoring Prometheus into a scratch
namespace would run a second Prometheus (about 600 MiB) on a master with under 1.5 GiB free, which breaks the stop threshold, so its restore
needs a resource modifier that keeps the restored pod from running the application. The Synapse media backup waits until the `shared-postgres`
pod carries the `pgdata` exclusion (draft PR 1565), because the `matrix` namespace also holds that volume.

## T046 (part): restore tests of `couchdb-data`, Prometheus and Alertmanager (2026-10-04T06:24Z to 07:17Z)

### couchdb-data: passed

Backup `first-couchdb-20261004`: `Completed`, 25 of 25 items, 14.8 MB of data, no errors. Restore into `restore-test-couchdb`: `Completed`, 4
warnings (all benign). The databases were compared logically from inside both pods (credentials taken from the pod's own environment,
never printed): the four databases (`_global_changes`, `_replicator`, `_users`, `obsidianlivesync`) have identical document counts and
identical SHA-256 of every document id and revision, including the 3,068 documents of `obsidianlivesync`.

### monitoring: backup passed, restore passed, and a near miss

Backup `first-monitoring-20261004`: `Completed`, 237 of 237 items, no errors; the Prometheus TSDB (1.17 GB) uploaded in about 90 s. Node memory
stayed at 76 to 79%.

**Near miss (06:31Z).** To keep a second operator and a second Prometheus out of the cluster, I restored only the Prometheus and Alertmanager
pods and volumes, selecting them by label and listing only `pods` and `persistentvolumeclaims`. Because PersistentVolumes were left out, Velero
kept `spec.volumeName` on the restored PVCs, so the scratch PVCs named the **live** Prometheus and Alertmanager volumes. They stayed unbound only
because those volumes are already bound to the live claims; had a restored pod started, the data restore would have written backup data into the
live volume. Nothing was written. I deleted the scratch namespace at once and confirmed the live PVs were still bound to the live claims, the live
pods were running, and Prometheus had 0 restarts (Alertmanager's 2 restarts date from 2026-09-27).

What I changed because of it:

- `scripts/hetzner-volume-verify/check-restored-pvcs.sh` (tests first, 7 bats tests): run it after a restore and before any restored pod runs; every
  PVC in the scratch namespace must have no volume yet or one bound to that same PVC, and an unreadable volume or namespace fails closed.
- Rules for every restore test from now on: include `persistentvolumes` in `includedResources` (the working configuration, as in the ntfy and
  couchdb restores: Velero provisions a new volume and leaves the live one alone); restore pods and their PVCs in **one** restore, because Velero
  creates the data-restore objects only for volumes whose PVC it restored in the same restore (a two-stage split left the pods waiting forever);
  run the guard straight after.

**Method that worked.** A Restore with `includedResources: [persistentvolumeclaims, persistentvolumes, pods]` and `orLabelSelectors` for the two
applications, after a first restore of Secrets, ConfigMaps and ServiceAccounts, with a resource modifier (a ConfigMap in `velero`) that swaps the
Prometheus container for `busybox` running `sleep` (the real image is distroless, and a second Prometheus would take about 600 MiB), and sets
resource limits on every restored container (the `require-resource-limits` policy applies to a scratch namespace even though `monitoring` is
exempt). A `remove /spec/volumeName` patch in the modifier was unnecessary once PVs were included (it errored on a missing key, harmlessly).

**Result.** All four volume restores `Completed`. The guard passed: both scratch PVCs bound to their own new volumes. Prometheus: 14 TSDB blocks
restored; the 13 that also exist on the live volume have identical `chunks/000001`, `index`, `meta.json` and `tombstones` (52 files, byte for
byte, compared against the live volume read-only through a root debug pod); one restored block was compacted away on the live side since the
backup, and one live block is newer than the backup. The write-ahead log and head chunks restored too. (An earlier "differing" result came from my
own digest line including `du` disk usage, which differs between filesystems; the file comparison settled it.) Alertmanager's `nflog` and
`silences` are empty on both sides. The restored Prometheus pod took 10 minutes to terminate because `sleep` ignores SIGTERM and Prometheus pods
get a 600 s grace period.

**Decision for T046:** keep the crash-consistent Velero file copy for Prometheus. The snapshot API is not needed: the restored blocks are intact
and the head and WAL are present for Prometheus to replay.

Cleaned up: scratch namespaces, their volumes, the Restore objects and the modifier ConfigMap are deleted; the root debug pods were deleted.

### Memory after Velero

Available memory is now about 1.0 GiB with 540 MiB of swap in use (T021's baseline was 1.55 GiB and 344 MiB), above the stop threshold of 700 MiB
but with less margin: the plugin and Velero cost about 500 MiB. A second database instance (T050 onward) is allowed up to 1 GiB, so Phase 4
needs a plan for headroom first (for example pausing a non-essential workload for the migration window).

## T042, T043: backup alerts and the first end-to-end test (2026-10-04T07:10Z to 07:55Z)

home-cluster PRs 1568 and 1569 merged: Velero's ServiceMonitor, a PodMonitor for the `shared-postgres` and `ente-db` instances (the operator's own
lacks the `release` label this Prometheus selects on), and the PrometheusRule `hetzner-backup-alerts` (seven alerts). Every metric the rules use was
read from live output first, and after the merge each has a series in Prometheus (Velero up; `cnpg_collector_last_available_backup_timestamp`,
`cnpg_pg_stat_archiver_failed_count` and `..._seconds_since_last_archival` for both clusters) and all rules report health `ok`. Velero exports no
storage-location metric, so none is used.

### A gap found by testing, and fixed

`VeleroBackupFailed` first watched only `velero_backup_failure_total` and `velero_backup_partial_failure_total`. A scheduled backup pointed at a
storage location the role cannot use (a scratch location with prefix `cnpg`) ended `FailedValidation` with `backup can't be created because
BackupStorageLocation test-denied is in Unavailable status`, and after that run the metrics for the schedule were `failure_total` 0,
`partial_failure_total` 0 and `validation_failure_total` 1. A broken bucket policy or an expired credential, the likeliest way these backups
fail, would therefore not have alerted until `VeleroScheduleStale` fired 26 hours later. PR 1569 adds the validation counter to the rule.

### End to end (VeleroBackupFailed)

With the corrected rule and the test schedule still running (one failing backup every 2 minutes): the alert went `pending` at 07:32, `firing` at
07:37 after its 5 minute hold, with the right labels (`schedule=alert-test`, `severity=critical`); Alertmanager held it with receiver `ntfy` and
no failed webhook notifications; the ntfy bridge logged `Successfully forwarded alert to ntfy` at 07:37:30Z, one group-wait (30 s) later. So the
chain rule, Prometheus, Alertmanager, bridge, ntfy works.

Cleanup: the test schedule, storage location, backups and namespace are deleted. The alert stayed firing for a while after the schedule was gone
because `increase(...[1h])` keeps seeing the old pod's samples until they age out of the one hour window: an alert on a failed backup clears about
an hour after the last failure, by design. A silence for exactly that test series (until 09:09Z) stops it re-notifying.

### What T043 has and has not proved

Proved: the failure path of `VeleroBackupFailed` and the delivery chain. Not forced: `VeleroScheduleStale`, `VeleroDown`, `DatabaseBaseBackupStale`,
`DatabaseHasNoBackup` (it is `pending` now for `shared-postgres`, and will fire after 24 hours without a backup unless T031 lands first),
`DatabaseWALArchivingFailing` and `DatabaseWALArchivingStale`. Their expressions are checked against real series but not exercised; a `promtool`
unit test of them is the cheap next step. T043 stays open for those.

## T045, T047 (part): the staging pod and the Grafana restore test (2026-10-04T09:26Z to 10:20Z)

`scripts/hetzner-volume-verify/staging-pod.yaml` is a minimal pod (busybox `sleep`, resource limits, the claim mounted **read-only**) that lets Velero's
file-system backup reach a volume whose workload is scaled to zero. Grafana has 0 replicas, so its volume was never backed up by the daily schedule.

**Backup.** With the staging pod running against `monitoring/kube-prometheus-stack-grafana`, a Backup selecting the pod and the Grafana claim by label:
`Completed`, 31 of 31 items, the data volume 161,766,537 bytes (598 files), no errors. A live listing taken from the staging pod beforehand matched in count
and total size.

**Restore, and a flaw in my own template.** The first restore into a scratch namespace hung for 17 minutes: the data-restore object existed but never started
and the pod stayed in its restore init container. Cause: the restored pod inherits the read-only mount, so the data restore has nowhere to write. Deleting
that restore then hung on a finalizer of the never-started data-restore object (its pod and namespace were gone); I removed the finalizers of my own
leftover test objects by hand (the node-agent controller re-added the one on the data-restore object, so the Restore's finalizer was removed instead and the
orphan deleted). The retry used a resource modifier that makes only the restored copy writable (the live staging pod stays read-only); the template's header
now says so.

**Result.** The retry `Completed`: the guard (`check-restored-pvcs.sh`) passed, the data restore reported exactly 161,766,537 bytes, and a path, size and
SHA-256 listing of every file on the live volume (from the read-only staging pod) against the restored volume has **598 files on each side and 0
differences**, including the 12 MB `grafana.db`. With no application running on either side, the comparison is exact bytes, so this one is stronger than the
logical comparisons used for the databases. Cleaned up: the staging pod, the scratch namespace and its volume, the Restore objects and the modifier are
deleted; the live Grafana claim is still `Bound`.

Still open for T047: the Minecraft world (`minecraft-create-arkana-data`, 50 Gi), which is larger and is better done with T044's timing in hand.

## T044: a 64 GiB upload from an encrypted volume (2026-10-04T09:25Z to 10:38Z)

A throwaway 70 Gi claim on `hcloud-volumes-encrypted` was filled with 64 GiB of incompressible data (64 files from `/dev/urandom`, about 40 MB/s to
write), then backed up by Velero while a watchdog logged master memory every minute and was set to delete the backup if available memory fell under
700 MiB or swap passed 1 GiB.

| Measure | Result |
|---|---|
| Backup | `Completed`, 68,719,476,741 bytes (64 GiB), no errors, no warnings |
| Duration | 10:19:08Z to 10:38:10Z: 19 minutes, about 60 MB/s |
| Credential errors in the node-agent log (`expired`, `InvalidIdentityToken`, `AccessDenied`, `credential`) | none |
| Master memory during the run | minimum available **732 MiB** (threshold 700), maximum swap 713 MiB (threshold 1 GiB); node at 78% afterwards |
| Velero server memory | about 330 MiB of its 512 MiB limit; the hosting pod about 245 MiB of its 512 MiB limit |
| Encrypted volume under Kopia | read and uploaded normally |

**What this did not prove.** The point of the test was credential refresh: the web identity credentials last one hour, and an upload that outlives them
must keep working. At about 60 MB/s the whole 64 GiB finished in 19 minutes, so the credentials never expired and the refresh path was **not exercised**.
Reaching an hour would take about 200 GB, which is not worth that load on this master. Judgement: the case only arises for an upload longer than an hour,
and the largest household volume is the 50 Gi Minecraft world, about 15 minutes at this rate; if a volume ever approaches 200 GB, or a backup fails near
the one hour mark, this is where to look. `VeleroBackupFailed` would report it. T044 is therefore left open for the owner to accept or to ask for a longer
run.

**What it did show.** A 64 GiB backup is possible on this master but leaves almost no memory margin: the minimum of 732 MiB is 32 MiB above the stop
line, and swap climbed to 713 MiB. A backup of this size must not overlap a database migration or any other large job (T021's no-overlap rule holds), and
Phase 4 needs real headroom before it starts.

Cleanup: the test backup was removed with a `DeleteBackupRequest` (Kopia frees the blobs at its next maintenance run, so up to 64 GiB stays in the bucket
until then), the namespace and its volume were deleted (no `enc-test` volume remains), and the watchdog was stopped.

## T047: the Minecraft world, backed up and restored (2026-10-04T10:55Z to 11:07Z)

`minecraft-create-arkana-data` is a 50 Gi plain claim, with 5.8 GiB used (6,197,258,417 bytes in 5,775 files, 1,856 of them `.mca` region files), and
both Minecraft Deployments are at zero, so Velero could not reach it before. The `minecraft` namespace allows privileged pods and holds only this volume,
so the staging pod from T045 ran against the live claim (read-only) and the Backup covered the whole namespace.

| Step | Result |
|---|---|
| Live listing (path, size, SHA-256 of every file, from the staging pod) | 5,775 files, 6,197,258,417 bytes, no errors, 2 min 18 s to hash |
| Backup `first-minecraft-20261004` | `Completed`, 38 of 38 items, no errors or warnings, data volume 6,197,258,417 bytes, **2 min 34 s** (about 40 MB/s) |
| Restore into `restore-test-minecraft` (PVs, claims and the pod, with the writable-copy modifier) | `Completed`, about 3 min 20 s, the data restore reported 6,197,258,417 bytes |
| `check-restored-pvcs.sh` straight after the restore started | passed: the scratch claim bound to its own new volume |
| Live against restored listing | **5,775 files on each side, 0 differences**, 1,856 region files on each side |

With no server running on either side the comparison is exact bytes. This proves the backup and the restore of the files; it does not yet prove that the
world loads: `check-world.sh` (read every chunk of every region file, T092 to T094) and a short game session (T077) are the checks for that, and are still
to do. Timing for the real world backups: about 2.5 minutes for the present 6 GiB, so the 2 hourly schedule is far inside its interval.

Cleaned up: the staging pod, the scratch namespace and its volume, the Restore object and the modifier are deleted; the live claim is still `Bound`.

**T047 is done.** T046 remains open only for `matrix-stack-synapse-media`, which waits for the `shared-postgres` pod to carry the `pgdata` exclusion (T031).

## check-world.sh on the real Minecraft world (T093)

2026-10-04T11:47:04Z: the six `region` directories of the live world (1,344 `.mca` files) were copied read-only through the staging pod and read with
`check-world.sh`: `chunks_read=178391 unreadable=0 files=1344`, exit 0, about 3 s. Positive controls on a throwaway copy: a corrupted chunk and a truncated
file were each reported (exit 1). The local copy and the staging pod are deleted. Limits: `.mcc` external chunks are not read, and the LZ4 framing is
untested on real data (this world uses zlib).

## T029 to T031: shared-postgres backs up through the Barman Cloud Plugin (2026-10-04)

Merged home-cluster#1565 (ObjectStore `s3://ajj-backups/cnpg-hetzner/shared-postgres`, daily `ScheduledBackup`, `plugins` with
`isWALArchiver`, the `pgdata` exclusion for Velero, IRSA role `hetzner-cnpg-backup-shared-postgres-irsa`) at 16:12:37Z on a Sunday,
outside the weekday window, with `check-no-call.sh` printing `calls=2`. The owner chose to go ahead and drop the calls ("do 2 as it
unblocks us"). A fresh encrypted safety dump (139 MB, `pg_dumpall`, end marker checked) was taken at 16:11Z first.

| Step | Result |
|---|---|
| Pod restart to add the plugin sidecar and the new service account | Terminating 16:14:32Z, Ready 16:18:05Z: **about 3.5 minutes**, nearly all of it the 180 s `smartShutdownTimeout` wait (pooled Synapse/MAS/niks3 connections never close on a smart shutdown); the new pod itself took about 15 s |
| Applications | Synapse and MAS reconnected on their own (MAS restarted 6 times while the database was away); no pod stayed failing |
| Cluster | `Cluster in healthy state`, `ContinuousArchiving=True`, WAL archived to the bucket |
| First base backup (`shared-postgres-first-20261004t162000`) | **failed** after 37 s: `rpc error: code = Unavailable … EOF`. Cause: the plugin sidecar was **OOMKilled at its 128 Mi limit** (the limit set in `objectstore.yaml`); `barman-cloud-backup` compresses the whole data directory while it uploads. WAL archiving, which needs little memory, was unaffected |
| Fix (home-cluster#1579) | sidecar limit 512 Mi, request 128 Mi; the sidecar only reads its resources at pod creation, so the pod was restarted once more at 16:23:13Z (calls were 0): Terminating to Ready took about 3.3 minutes |
| Second base backup (`shared-postgres-first-20261004t162639`) | `completed`, 16:26:40Z to 16:27:48Z (**68 s**), sidecar 0 restarts |
| Recovery window | `ObjectStore.status.serverRecoveryWindow`: `firstRecoverabilityPoint` and `lastSuccessfulBackupTime` both `2026-10-04T16:27:48Z` (`Cluster.status.firstRecoverabilityPoint` stays empty with the plugin method; read the ObjectStore status instead) |
| Velero | the pod carries `backup.velero.io/backup-volumes-excludes: pgdata`, so the disabled `matrix` Velero schedule can be enabled |

Lesson recorded: a sidecar setting is applied only when the pod is created, so a wrong value costs a second restart. The restart blip is
dominated by `smartShutdownTimeout` (180 s); lowering it for planned restarts would cut the connection-refusing window.

## T032: ente-db backs up through the Barman Cloud Plugin (2026-10-04)

Done at the owner's request ("do the ente-db plugin conversion now"), on a Sunday evening, before the plugin's restore proof on
`shared-postgres` (T035) that the task asked for first; the old chain was kept so nothing was lost by going ahead.

| Step | Result |
|---|---|
| Before | fresh encrypted `pg_dumpall` (33 MB, end marker checked) at 20:45:16Z; on-demand in-tree backup `ente-db-pre-plugin-20261004t204518` `completed` (recovery point since 2026-09-04) |
| Validation | the same `Cluster` with both `spec.backup.barmanObjectStore` and `spec.plugins` is **rejected** by the webhook ("Cannot enable a WAL archiver plugin when barmanObjectStore is configured"); a server-side dry run with the Flux field manager (which removes `spec.backup`) is accepted, so the change ships as one commit |
| Change (home-cluster#1583) | `ObjectStore ente-db` (`s3://ajj-backups/cnpg-hetzner/ente-db`, IRSA role `hetzner-cnpg-backup-ente-db-irsa`, sidecar 128 Mi request / 512 Mi limit from the start), `spec.plugins` with `isWALArchiver`, service account annotation, `pgdata` Velero exclusion, `ente-db-daily` `method: plugin`, the `ente` Kustomization waits for `cnpg-barman-plugin`, and the old Hetzner Object Storage archive kept as the `ente-db-hetzner-os` externalCluster |
| Pod restart | Terminating 20:49:37Z, Ready 20:53:04Z: about **3.5 minutes** (the 180 s smart-shutdown wait again) |
| Cluster | `Cluster in healthy state`, `ContinuousArchiving=True`, archiver `archived_count 2235`, last file archived |
| First plugin base backup | `ente-db-first-20261004t205311` `completed`, 20:53:12Z to 20:53:24Z (**12 s**, same as the old in-tree backups), sidecar 0 restarts |
| Recovery window | `ObjectStore.status.serverRecoveryWindow`: first recoverability point and last successful backup `2026-10-04T20:53:24Z` |
| Photo service | Museum pod kept running; its `/ping` failed only while the database was down (3 log lines) and returns `pong`; the public `/ping` returns 200. Signing in and opening an album was not exercised |

Open (T033): a restore test of the new plugin chain (as T035 does for `shared-postgres`) and then removing the old bucket and the
backup use of `ente-s3` (Museum still needs `ente-s3` for photo storage). The old archive stays until then.

## T033, T035: the plugin chains restore (2026-10-04)

The IAM trust policy of each backup role names only the live service account (`matrix:shared-postgres`, `ente:ente-db`), so a scratch
namespace cannot assume it. For the test the live service account's token was requested with `kubectl create token --audience
sts.amazonaws.com --duration 1h`, exchanged for 1 hour credentials with `sts assume-role-with-web-identity`, stored in a Secret in the
scratch namespace and referenced by a copy of the `ObjectStore` (read-only use: the scratch `Cluster` has no backup section). No value was
printed; the Secret went with the namespace and the credentials expired within the hour.

| | `shared-postgres` | `ente-db` |
|---|---|---|
| Scratch `Cluster` | `bootstrap.recovery` from the plugin (`externalClusters` with `plugin`), 10 Gi on `hcloud-volumes-encrypted` | same, with the pinned PostgreSQL 18.4 image |
| Time to a healthy cluster | 108 s | 118 s |
| Databases | `niks3` 607 MB, `synapse` 218 MB, `mas` 19 MB, `app` | `ente` (81 tables) |
| Compare against the live primary | `niks3` (8 tables) and `app` identical; `mas` (33 tables) differs in 6 and `synapse` (173) in 4, all churning tables (OAuth tokens and sessions, queue jobs, devices, presence, stream positions, user IPs) written since the last archived WAL | **all 81 tables identical**, `postgres` 0 tables |

Namespaces, volumes and credentials were deleted afterwards (0 scratch PVs).

## T036, T037: the stale restore Secret is gone (2026-10-04T22:2xZ)

`matrix/cnpg-restore-aws-creds` held the keys `ACCESS_KEY_ID` (20 bytes), `SECRET_ACCESS_KEY` (40) and `SESSION_TOKEN` (932): expired temporary
credentials created on 2026-09-13, not a long-lived key. Nothing referenced it (no pod volume, `env` or `envFrom`, no `Cluster`, no manifest
in `home-cluster`), and the restore tests no longer need it, so it was deleted; `shared-postgres` stayed healthy and no Secret of that name
remains (SC-012, FR-016).

## T048, T049: backups proven (2026-10-04T22:30Z)

Latest completed backup per volume (UTC):

| Volume group | Backup | Completed |
|---|---|---|
| `couchdb` | Velero `couchdb-enc-20261004t141409z` | 14:14:54Z |
| `ntfy` | Velero `ntfy-enc-20261004t142839z` | 14:29:26Z |
| `monitoring` (Grafana, Alertmanager, Prometheus) | Velero `monitoring-enc-20261004t151335z` | 15:15:37Z |
| `matrix` media | Velero `matrix-media-staging-20261004t172840z` | 17:29:03Z |
| `shared-postgres` | CNPG plugin `shared-postgres-final-20261004t221105` | 22:12:31Z |
| `ente-db` | CNPG plugin `ente-db-post-switch-20261004t211517` | 21:15:30Z |
| Minecraft world | Velero `first-minecraft-20261004` (its schedules are still disabled, see the Minecraft work) | 11:00:54Z |

Every volume has been restored from its backup and compared (files byte for byte for the Velero volumes; every logged table for the two
databases, from the plugin chain through `restore-test` clusters). **Backups are proven as of 2026-10-04T22:30Z**; storage was proven at
05:52:24Z, so the 7 day window of FR-012 ends 2026-10-11T22:30Z. Nine of ten data volumes are already encrypted; the Minecraft world is the last.

## T080 to T084, T085: the RCON image is live; the Velero hooks cannot reach a game node (2026-10-05)

| Step | Result |
|---|---|
| RCON in the image (T080, T081; nix-config#470) | merged. Its `flake-check` had failed three times for an unrelated reason: two hand-written CurseForge URLs in `arkana-mods-extras.nix` were zero padded (`files/7956/082/`), which CloudFront answers with an S3 403 (a missing key). Not the runner, not the User-Agent. Fixed in nix-config#494 (the pinned hashes match the content at the right URL; all 370 literal URLs in the package checked) with a guard script in the PR check and as a pre-commit hook |
| Image build and push (T082) | tag `arkana-aeronautics-v1.5-aero-1.2.1-64`: the build was cached (1.5 min) but Publish failed at `skopeo login` (`mkdir /run/containers: permission denied`, the runner pod's user has no writable `XDG_RUNTIME_DIR`); fixed in nix-config#495 (`REGISTRY_AUTH_FILE` under `runner.temp`), then re-published with `workflow_dispatch` in 3 min. Image `ghcr.io/alisonjenkins/create-arkana-aeronautics-server:v1.5-aero-1.2.1-64-amd64`, digest `sha256:08200a26…`. The game node pool is amd64 only, so the deployment uses the `-amd64` tag |
| Deployment (T084; home-cluster#1592) | merged: the image tag, `RCON_PASSWORD` from `minecraft-rcon`, and the Velero pre-hook (`save-off`, `save-all flush`, on-error Fail) and post-hook (`save-on`). The backend is at 0 replicas, so nothing restarted |
| Live test (T085) | the server was scaled to 1 by hand with no proxy and no player: pod Ready 3 minutes after the scale (the game node came up on demand). Then `kubectl logs` and `kubectl exec` to it **failed**: `tls: failed to verify certificate: x509: certificate is valid for 127.0.0.1, ::1, 46.225.12.231, not 10.0.1.1`. A real Velero backup of the namespace showed the same: `Error executing hook … hookPhase=pre … error dialing backend: tls: failed to verify certificate`, and the backup was `PartiallyFailed` (the `Fail` setting did its job: no unquiesced backup was taken). The server was scaled back to 0 afterwards |

**Cause.** Worker nodes join k3s with `--node-ip` set to their public address (`lib/hetzner-node-services.nix`: the hcloud CCM rejects a private
node-ip). k3s signs the agent's kubelet serving certificate from that `--node-ip` only (the agent sends it in the `k3s-Node-IP` header), so
the certificate covers the public IP and the node name. The hcloud CCM then adds the private IP as the node's `InternalIP` (`10.0.1.1`), and
the API server dials the `InternalIP`, which the certificate does not cover. Everything that goes through the API server to a game node
fails: `kubectl logs`, `kubectl exec`, `kubectl debug node`, port-forward and Velero's exec hooks. The master's certificate is fine, which is why
the same hooks work there. Velero's file-system backup itself does not use this path (the node agent reads the volume locally).

**Consequence.** The three `minecraft-*` schedules must stay disabled: with the pre-hook set to `Fail` every run would end `PartiallyFailed`
(and alert). T085 stays open until the path works.

Options, none applied: (1) make the API server dial a name the certificate covers, for example
`--kube-apiserver-arg=kubelet-preferred-address-types=ExternalIP,InternalIP,Hostname` on the k3s server (needs a master change and a test; I
have not verified that the agent tunnel accepts the external address); (2) give the worker certificate the private IP, which needs a different
`--node-ip` strategy and a CCM check; (3) no exec hooks: quiesce through RCON from inside the cluster (the proxy or a small job) and open that one
path in the `minecraft-backend` network policy; (4) accept crash-consistent backups and rely on `check-world.sh` to detect a bad one.

## T085 to T087, T094, T095: the hooks work; the world restores (2026-10-05)

This supersedes the "cannot reach a game node" section above: that blocker is fixed, and the options listed there were refined (see
[ADR 0026](../../../docs/adr/0026-hetzner-worker-node-networking.md); `ExternalIP` first would have broken the master's own exec).

| Step | Result |
|---|---|
| Fix | the k3s server dials kubelets by node name (`kubelet-preferred-address-types=Hostname,InternalIP,ExternalIP`): merged in nix-config#497, applied live to the master with a `config.yaml.d` file and a detached k3s restart (API back in about 20 s, pod restart counts unchanged, `calls=0` first). Right after the restart the API proxy briefly answered 502 for about 40 s and then cleared |
| Live test (T085) | server scaled to 1 with no proxy and no player: `kubectl logs` and `exec` reach the game pod, `mcrcon` answers (`list`, `save-off`, `save-on`). A Velero backup of the running server: `Completed`, 69 s, 6,198,378,481 bytes, no errors; the server log shows `Saved the game` (the pre-hook flush), saving paused during the copy and `Automatic saving is now enabled` (the post-hook). No player was connected, so the hitch length for one player is **not measured** |
| Restore (T094) | the same backup restored into a scratch namespace: the data restore `Completed` (6,198,378,481 of 6,198,378,481 bytes), `check-restored-pvcs.sh` passed (the claim bound to its own new volume), and `check-world.sh` on the restored region files: `chunks_read=178391 unreadable=0 files=1344`, exit 0. Not done: the same check on a backup taken while a player was building |
| Schedules (T086, T087; home-cluster#1593) | `minecraft-2h`, `minecraft-daily` and `minecraft-weekly` enabled. First `minecraft-2h` run 06:00:57Z: `velero-minecraft-2h-20261005060057`, `Completed`, TTL 72 h, no errors (the server was down, so no volume was backed up, as expected) |
| Runbook (T095) | [`docs/hetzner-minecraft-world-restore.md`](../../../docs/hetzner-minecraft-world-restore.md) |

While doing this a second fault showed up on fresh game nodes (a stuck Cilium host datapath that stalled the CSI driver and made the first
restore pod unable to mount its volume); cause, fix and evidence are in ADR 0026 (home-cluster#1594 and #1595).
