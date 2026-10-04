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
