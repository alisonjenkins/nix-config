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
