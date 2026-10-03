# Data model: Encrypt the household's data volumes

Entities, their fields, and the states a volume migration moves through. Sizes are from the
kubelet on 2026-10-03.

## Volume inventory

Nine volumes, eight services. "Method" is the migration path chosen in `research.md`.

| Volume | Namespace | Used / capacity | Owner workload | Kind | Backup method | Migration method |
|---|---|---|---|---|---|---|
| `shared-postgres-1` | matrix | 1.5 GiB / 19.5 GiB | CNPG cluster `shared-postgres` | database | CNPG backups | CNPG replica on new class, switchover |
| `matrix-stack-synapse-media` | matrix | 0.8 GiB / 9.7 GiB | StatefulSet `matrix-stack-synapse-main` | files | Velero (fs) | copy job |
| `ente-db-1` | ente | 0.7 GiB / 9.7 GiB | CNPG cluster `ente-db` | database | CNPG backups | CNPG replica on new class, switchover |
| `couchdb-data` | couchdb | 16 MiB / 9.7 GiB | Deployment `couchdb` | database files | Velero (fs) | copy job |
| `prometheus-...-db-...-0` | monitoring | 0.9 GiB / 9.7 GiB | StatefulSet (operator) | time series | Velero (fs, snapshot API) | copy job |
| `alertmanager-...-db-...-0` | monitoring | 2 MiB / 9.7 GiB | StatefulSet (operator) | files | Velero (fs) | copy job |
| `kube-prometheus-stack-grafana` | monitoring | n/a (scaled to 0) | Deployment, 0 replicas | SQLite | Velero (fs, staging pod) | copy job |
| `ntfy-data` | ntfy | 2 MiB / 9.7 GiB | Deployment `ntfy` | SQLite | Velero (fs) | copy job |
| `minecraft-create-arkana-data` | minecraft | n/a (scaled to 0) / 50 Gi | Deployment, 0 replicas | world files | Velero (fs, staging pod) | copy job |

The total of used data is under 5 GiB. Copies are fast. The limit is coordination and checks,
not transfer time.

## Entities

### StorageClass `hcloud-volumes` (existing)

- Default class today. `reclaimPolicy: Delete`, `WaitForFirstConsumer`, volume expansion on.
- Created by the Helm chart. Stays in place so existing volumes keep a valid class.
- At the end of the feature it is no longer the default and no volume uses it.

### StorageClass `hcloud-volumes-encrypted` (new)

- Same as above, plus the parameters that reference the passphrase Secret.
- Becomes the default class after the throwaway-volume test passes.
- `reclaimPolicy` stays `Delete`; protection of old volumes uses `Retain` on the PV instead
  (see the state machine).

### Passphrase Secret

| Field | Value |
|---|---|
| Name and namespace | one Secret in `kube-system` |
| Key | `encryption-passphrase` |
| Stored in | the home-cluster repo, SOPS-encrypted, and the owner's password manager |
| Rotation | none planned; a change would need every volume re-keyed |

One passphrase covers every encrypted volume (spec assumption).

### Backup repository (Velero)

| Field | Value |
|---|---|
| Backup location | existing S3 bucket, prefix `velero-hetzner/` |
| Uploader | Kopia, file-system backup |
| Repository password | own secret, set before the first backup, kept in the password manager |
| Schedule | daily, staggered, with a TTL (Minecraft has its own, below) |
| Credentials | web identity (IRSA): a role limited to its prefix, on the Velero server and node-agent service accounts. Session long enough for an upload |

### Backup repository (databases)

| Field | Value |
|---|---|
| Backup location | existing S3 bucket, prefix `cnpg-hetzner/<cluster>/` |
| Method | Barman Cloud Plugin: continuous WAL archiving plus a daily base backup |
| Recovery target | at most 5 minutes of loss |
| Credentials | web identity (IRSA): a role limited to its prefix, on the database service accounts |

### Minecraft world backup policy

| Tier | Spacing | Kept for |
|---|---|---|
| Frequent | every 2 hours while the server runs, plus once after the last player leaves | 3 days |
| Daily | one a day | 90 days |
| Weekly | one a week | 1 year |

Each backup is a consistent copy: the server is told to save and pause writes before the copy
and resume after it. Restoring a chosen backup goes to a scratch namespace and never touches
the live world.

### Cluster signing identity (existing)

| Field | Value |
|---|---|
| Issuer | `https://s3.eu-west-1.amazonaws.com/hetzner-k8s-irsa`, published by the Terraform module `hetzner_irsa` |
| Webhook | `pod-identity-webhook` in `kube-system`, injecting the token and role ARN into annotated service accounts |
| Used today by | `matrix:shared-postgres`, with the read-only restore role |
| This feature adds | two roles on this issuer, one for Velero and one for the database backups |

### Migration run

One run moves one volume. The fields are the record the operator keeps, in UTC (spec FR-011).

| Field | Meaning |
|---|---|
| `volume` | the volume from the inventory |
| `window` | the no-call window used, where chat is affected |
| `snapshot_taken_at` | the moment the comparison snapshot was taken at the switch |
| `compare` | result of the data comparison: row counts and checksums, or file counts and checksums |
| `health` | result of the service health checks on the new volume |
| `functional` | result of the functional check (send and read a message, open known media) |
| `backup_after` | time of the fresh backup of the new volume |
| `old_removed_at` | when the old volume was destroyed |
| `outcome` | verified, rolled back, or aborted, with the reason |

## State machine: one volume

```text
plain ──(backup proven)──> backed-up ──(copy ready)──> copied
copied ──(switch)──> switched ──(verify passes + fresh backup)──> verified
verified ──(destroy old, within 24 h)──> encrypted
switched ──(verify fails)──> rolled-back (old volume is current again)
```

- `plain`: on the old class, no proven backup.
- `backed-up`: a restore test passed (FR-004, FR-015). Nothing moves before this.
- `copied`: the new encrypted volume holds a current copy and, for a database, has caught up.
- `switched`: the service uses the new volume. The old PV has `Retain`, so the claim cannot
  destroy it.
- `verified`: all three checks passed (FR-006) and `backup_after` exists.
- `encrypted`: the old volume is gone. This is the end state and satisfies SC-007.
- `rolled-back`: the old volume is intact and in use, or can be switched back to. The new
  volume is removed.

Only `verified` allows the old volume to be destroyed (FR-007).

## Validation rules (from the requirements)

- No volume enters `copied` unless its service has a `backup_after`-style restore-tested
  backup (FR-004, FR-015, SC-009).
- No `switched` volume is destroyed until `compare`, `health` and `functional` are all
  passing (FR-006).
- Steps that interrupt chat only run when no call is active (FR-009).
- An old PV must have `Retain` before its claim is removed (FR-007).
