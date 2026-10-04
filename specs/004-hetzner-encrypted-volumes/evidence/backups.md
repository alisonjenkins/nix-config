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
