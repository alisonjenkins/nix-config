# AWS evidence: backup roles (T005 to T008)

Applied 2026-10-03 by the owner from the `feat/hetzner-backup-irsa` branch of the Terraform repository, with a targeted plan:
`-target=module.hetzner_backup_irsa -target=aws_iam_role_policy.hetzner_backup -target=aws_s3_bucket_policy.policy`.

Result: 6 added, 1 changed, 0 destroyed.

| Role | Trusts service account | Prefix in `ajj-backups` |
|---|---|---|
| `arn:aws:iam::918821718107:role/hetzner-velero-irsa` | `velero:velero` | `velero-hetzner` |
| `arn:aws:iam::918821718107:role/hetzner-cnpg-backup-shared-postgres-irsa` | `matrix:shared-postgres` | `cnpg-hetzner/shared-postgres`, plus read of the old restore prefix |
| `arn:aws:iam::918821718107:role/hetzner-cnpg-backup-ente-db-irsa` | `ente:ente-db` | `cnpg-hetzner/ente-db` |

Changed: the `ajj-backups` bucket policy. By the Terraform configuration, the deny's `StringNotLike` principal list keeps its five existing roles and gains these three. The plan showed the whole policy as "known after apply" (the new ARNs did not exist yet) and the apply reported only "Modifications complete". The policy has not been read back from AWS: to confirm, run `aws s3api get-bucket-policy --bucket ajj-backups` and check the list.

## Baseline (T004)

The untargeted `tofu plan` on the branch was not empty: 18 to add and 25 to change, none to destroy. Besides the roles above it held unapplied resources from the owner's earlier local commits (Roles Anywhere DNS role, master EIP and Route 53 records, launch-template AMI drift). They were left out of this apply on purpose and are still pending.

# Cluster evidence (T009 to T012)

- home-cluster PR 1560 (matrix and ente network policies) merged and applied 2026-10-03T17:24Z. The `shared-postgres` primary then restarted without a switchover (about 2 minutes, 17:27Z to 17:29Z) and both clusters reported `Cluster in healthy state`. The `Instance Status Extraction Error` is gone. The authentication service crash-looped 3 times during the restart and recovered.
- home-cluster PR 1561 merged: Secret `hcloud-volume-passphrase` in `kube-system` exists in the cluster (key `encryption-passphrase`). The 1Password copy is still to do.

# T008a: the backup role policy fix, applied and re-probed (2026-10-04)

Applied by the owner with a targeted plan (`aws_iam_role_policy.hetzner_backup`): 0 to add, 3 to change, 0 to destroy (`velero`, `cnpg_shared_postgres`,
`cnpg_ente_db`). I read the saved plan first: `s3:ListBucket` on each role's own prefix uses `StringLikeIfExists`, `s3:ListBucketMultipartUploads` is its
own statement without a condition, `GetBucketLocation` is kept, and the read-only access to the old archive is unchanged.

Re-probe from a scratch pod in `matrix` (ServiceAccount `shared-postgres`, role `hetzner-cnpg-backup-shared-postgres-irsa`, projected `sts.amazonaws.com`
token), the same setup as the first probe in `backups.md`:

| Check | Before | After |
|---|---|---|
| `barman-cloud-check-wal-archive` | `HeadBucket … 403 Forbidden` | no error |
| `HeadBucket` | denied | allowed |
| multipart create, list parts, list uploads, abort | list uploads denied | allowed |
| list, put or get under `cnpg/` or `velero-hetzner/`; put or get outside the role's prefix | denied | still denied |
| list, put, get, delete under the role's own prefix; `GetBucketLocation` | allowed | allowed |
| list at the bucket root | denied | **allowed** (see below) |

**Accepted trade-off.** `HeadBucket` and a root listing both reach IAM with no `s3:prefix` value, so no condition can allow one and deny the other: with
`StringLikeIfExists` a root listing is allowed. Each role can now see the object **names** in `ajj-backups`, but cannot read, write or delete outside its own
prefix. The aws-k3s backup roles already have an unconditioned `ListBucket`.

The stray multipart upload the first probe left (`cnpg-hetzner/shared-postgres/_iam-probe/mpu.bin`, started 06:00:54Z) was listed and aborted: 0 remaining.
The scratch pod is deleted. Velero's role has the same policy shape; Velero already worked (storage location `Available`, backups completed).
