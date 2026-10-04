# 0022. Encrypt every Hetzner data volume, behind a restore-tested backup

- Status: Proposed
- Date: 2026-10-03

## Context

None of the household's nine data volumes on the Hetzner cluster is encrypted. They are plain ext4
on Hetzner cloud volumes, on a single StorageClass, `hcloud-volumes`, that is also the default.

Backups are thin. The Matrix and cache databases (`shared-postgres`) have no backup configured on this
cluster (the cluster record shows no backup section and an empty recovery point), and neither do the
media store, the document database, monitoring, the notification server or the game server. Each of
those volumes has one copy. The photo database (`ente-db`) is the exception: it has had a working
in-tree CloudNativePG backup since 2026-09-04 (daily base backups, WAL archiving, 30 day retention) to
a Hetzner Object Storage bucket, using the account-wide `ente-s3` key. An earlier version of this
record said it had none; that was wrong. It still has to move to the plugin and web identity, because
the in-tree method is removed in CloudNativePG 1.31.0 and a long-lived key is not allowed for backups.

Two findings from the live cluster shaped the order of work:

- A Cilium policy, `postgres-policy`, allows ingress to the Matrix Postgres pods only on port 5432
  from Synapse, MAS and niks3. The operator log shows `dial tcp 10.42.0.57:8000: i/o timeout`, which
  is the `Instance Status Extraction Error: HTTP communication issue`. A second instance also cannot
  replicate through it. Fixed on 2026-10-04 by home-cluster PR 1560.
- The Hetzner CSI driver encrypts a volume only if its passphrase Secret value is non-empty. Confirmed
  in the driver source (`internal/volumes/mount.go`): with an empty passphrase it skips LUKS and mounts
  the plain disk, with no error. A volume that mounted is therefore not proof that it is encrypted.

The cluster already has web identity (IRSA): a self-hosted issuer, the pod-identity webhook, and the
`hetzner-cnpg-restore-irsa` role used today to read the old cluster's backups.

## Decision

- **Encrypt with a second StorageClass** `hcloud-volumes-encrypted` (LUKS through the CSI driver's
  `node-publish-secret-name`), defined next to the existing class in the `hcloud-csi` HelmRelease. It
  becomes the default only after a throwaway-volume test passes. Existing volumes cannot be converted
  in place, so each is copied.
- **Back up first.** Databases use the Barman Cloud Plugin (the in-tree method is deprecated and
  scheduled for removal in CloudNativePG 1.31.0). Other volumes use Velero with Kopia file backups.
  Both write to `ajj-backups` under their own prefixes, over IRSA, with one role per identity limited to
  its prefix. No long-lived storage key is kept on the cluster.
- **Move databases by replication**: a second instance on the encrypted class, a switchover,
  verification, then the old instance is removed. Other volumes move by a copy job with the service
  scaled to zero. Velero is used for backups and restore tests, not for the move.
- **Verify before removing.** One script checks the device is really LUKS, compares data against a
  snapshot taken at the switch, checks health and a functional use of the service, and requires a fresh
  backup. The old plain volume is removed within 24 hours of a pass, with no fixed waiting period.
- **Minecraft world backups** every 2 hours while it runs and once after the last player leaves,
  kept in tiers for up to a year, so a grief found weeks later can be rolled back.

## Alternatives rejected

- Encryption inside each application: differs per service and does not cover Prometheus, the world or
  the media store.
- The in-tree CloudNativePG backup method: removal is scheduled for 1.31.0 and the operator updates
  itself.
- IAM Roles Anywhere for Velero: needs a credential-helper sidecar on the server and every node-agent
  pod, and the chart has no sidecar value. IRSA already exists and is proven.
- Static IAM keys: rejected by the no-long-lived-keys requirement.
- Velero restore as the migration step: it recreates the claim itself and cannot restore into a
  pre-created one.
- A fixed soak period for the old plain volume: the owner wants plaintext gone as soon as the copy is
  verified, with the backup as the way back.

## Consequences

- Every volume has a restore-tested backup, and a failing backup alerts.
- After an old volume is removed, the way back is the backup, not the old volume.
- One passphrase covers all encrypted volumes. Losing it loses the data, so it lives in the encrypted
  config repository and in the owner's password manager.
- `hcloud-volumes-encrypted` has `reclaimPolicy: Delete`, like the old class. A mistaken `kubectl delete pvc` on a
  migrated volume destroys it, and once its old copy is removed only the backup remains. `Retain` would prevent
  that but leaves an orphaned Hetzner volume after every throwaway test. The decision is to keep `Delete` and
  protect each migrated volume with the backup; revisit if a claim is ever deleted by mistake.
- A Secret that exists but has no, or an empty, `encryption-passphrase` gives a silent plain volume on first
  mount (tested 2026-10-04, `evidence/storage.md`). A Kyverno policy on claim creation (task T025a) blocks it.
- Encryption protects data at rest on Hetzner's storage. It does not protect against someone with
  access to the cluster, because the passphrase is a cluster Secret. Node root disks and `emptyDir`
  scratch space stay unencrypted.
- Everything is encrypted within 7 days of the storage and the backups being proven.

## Evidence

Read-only queries on 2026-10-03: the StorageClass and PVs, the CloudNativePG cluster spec and operator
log, the Cilium policy, the Terraform repository and its bucket policy, and
`matrix/cnpg-restore-aws-creds` (key names only: it holds expired temporary credentials, not a key).
Upstream behaviour is from research reports with a stated confidence in
`specs/004-hetzner-encrypted-volumes/research.md`.

Built and applied by 2026-10-04, recorded in `specs/004-hetzner-encrypted-volumes/evidence/`: the three
IRSA backup roles and the bucket-policy exemption, the network-policy fix, the passphrase Secret, the
`hcloud-volumes-encrypted` class (not yet proven on a throwaway volume), and the verification and
removal scripts in `scripts/hetzner-volume-verify/`, with their tests. No backup runs and no volume has
moved yet.

## Revisit when

- The throwaway-volume test shows the missing-Secret case mounts plain text, which would add a policy
  that blocks it.
- CloudNativePG refuses a changed `storageClass` on an existing cluster, which switches the database
  move to a replica cluster.
- The Kopia credential refresh test fails inside the one hour IRSA session.
- The Hetzner CSI driver adds volume snapshots, which would let Velero use them.
