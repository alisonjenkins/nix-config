# Research: Encrypt the household's data volumes

Date: 2026-10-03. Each decision names its evidence, a confidence, and what is unproven. Anything
unproven becomes a rehearsal step in `plan.md`, not an assumption.

Sources marked "read" are live read-only queries on the cluster or reads of the repos. Sources
marked "docs" were gathered by research sub-agents from upstream documentation and the driver
and operator source. Their reports are second-hand, and the points they could not confirm are
listed as such.

## 1. Encrypted storage

**Decision**: A second StorageClass `hcloud-volumes-encrypted`, defined in the `hcloud-csi` Helm
release. It sets `csi.storage.k8s.io/node-publish-secret-name` and `-namespace` to a Secret
holding the key `encryption-passphrase` in `kube-system`. It stays non-default until the
throwaway-volume test passes, then becomes the default.

**Rationale**:

- The upstream driver formats a volume with LUKS only when the device has no filesystem. An
  existing plaintext volume mounted through the encrypted class fails with an error. So there
  is no in-place conversion, which matches the spec (docs, high).
- The passphrase is per StorageClass, not per volume (docs, medium-high). One passphrase covers
  every encrypted volume, as the spec assumes.
- The chart defines `storageClasses` as a list. Each item takes `name`, `defaultStorageClass`,
  `reclaimPolicy`, `annotations` and `extraParameters` (docs, high). It is not known whether
  a list replaces the default entry, so the old class must be re-listed explicitly (unverified).
- Online resize for an encrypted volume looks supported in the code (docs, medium-high), and
  is not documented as tested. Volumes only grow.
- `dm-crypt` is not a concern on this image: the master already runs a LUKS state volume, and
  the image ships `cryptsetup` (read).

**Risk found: silent plaintext.** The driver reads the passphrase from the Secret at publish
time. The sub-agent's reading of the code is that an empty passphrase skips encryption and
mounts plain text, with no error (docs, low; unconfirmed against the source). Treat it as
true. Consequences:

- The Secret MUST exist and be non-empty before the class is created.
- Every migration runs the "encryption is real" check first (`contracts/verification.md`,
  part 0), and it must not rely on the volume merely mounting.
- The first rehearsal deletes the Secret on a throwaway volume to see what actually happens.

**Alternatives considered**:

- Encrypt inside the application (database encryption, application-level storage). Rejected:
  it differs per service and does not cover Prometheus, Minecraft or the media store.
- Node-level full-disk encryption. Rejected: the volumes are network block devices attached
  to whichever node runs the pod, so the encryption has to be per volume.
- Per-volume passphrases. Rejected in the spec: more places to lose a key.

## 2. Passphrase storage

**Decision**: Generate a random passphrase, keep it SOPS-encrypted in the `home-cluster` repo,
and keep a copy in the owner's password manager (owner's choice, 2026-10-03).

**Rationale**: It matches how every other secret in `home-cluster` is handled. The password
manager copy is the independent second place that FR-003 requires.

**Alternatives considered**: An offline paper copy was offered and declined.

## 3. Database migration

**Decision**: For `shared-postgres` and `ente-db`, add a second instance on the new encrypted
class, wait for zero lag, switch over, verify, then destroy the old instance. The cluster name
and the `-rw` service stay the same, so applications are not reconfigured.

**Rationale**:

- CloudNativePG applies a changed `storage.storageClass` only to PVCs created afterwards.
  Existing PVCs and pods are untouched (docs, medium-high; GitHub issues #7639 and #8605).
- There is no official procedure. The only description is user-proposed: change the class,
  recreate replicas, promote, delete the old primary. For a one-instance cluster that means
  scaling to two instances and removing the old one (docs, medium-high).
- `kubectl cnpg promote CLUSTER INSTANCE` does a planned switchover. `kubectl cnpg destroy
  CLUSTER INSTANCE` removes an instance and its volumes. With `--keep-pvc` it keeps the
  volumes and marks them detached (docs, medium-high; checked against main, not the 1.30 tag).
- The old primary and the new replica share the master, and `podAntiAffinityType` is already
  `preferred`, so both can run on one node. No node pinning is needed in this feature.

**Unproven, so rehearsed first** (on a scratch cluster in a scratch namespace):

1. Whether the validating webhook accepts a changed `storageClass` on an existing cluster
   (docs, medium).
2. Whether a changed `affinity` restarts the existing primary (docs, low-medium). This feature
   does not change affinity, which avoids the question.
3. The exact promote and destroy flags in 1.30.1.

**Alternatives considered**:

- A replica cluster (`replica.enabled` with `bootstrap.pg_basebackup`), then promote, as a
  second `Cluster` object. It works, and it needs the new cluster's name in every client:
  Synapse, MAS and the niks3 DB URI. Kept as the fallback if rehearsal 1 fails.
- `pg_dump` and restore. Rejected as the primary path: it needs write downtime for the whole
  copy. It is still taken as a safety copy.

## 4. A prerequisite found in the cluster: the Postgres network policy

**Finding (read, high)**: the Cilium policy `postgres-policy` in `matrix` selects
`cnpg.io/cluster: shared-postgres`. It allows ingress only to port 5432 from `synapse-main`,
`matrix-authentication-service` and `niks3`. It allows egress only to the API server, DNS and
TCP 443 anywhere.

The operator log shows the effect:
`Get "https://10.42.0.57:8000/pg/status": dial tcp 10.42.0.57:8000: i/o timeout`. That is the
`Instance Status Extraction Error: HTTP communication issue`, and the same documented cause as
a blocked operator (docs, high).

**Decision**: Before anything else, extend the policy so that:

- the operator namespace (`cnpg-system`) can reach port 8000 on the instance pods;
- instance pods can reach each other on 5432 and 8000, for streaming replication and status;
- Prometheus can reach the metrics port (9187), if scraped.

A second instance cannot replicate without the pod-to-pod rules, and the switchover command
needs the operator's status channel. The `ente-db` cluster has its own policy and a healthy
status; it gets the same check.

## 5. Database backups

**Decision**: Use the Barman Cloud Plugin, not the in-tree `spec.backup.barmanObjectStore`.
Archive WAL continuously with a daily base backup, to the existing bucket under a Hetzner
prefix.

**Rationale**:

- The in-tree method is deprecated since 1.26 and is scheduled for removal in operator 1.31.0
  (docs: the 1.30 release notes, https://cloudnative-pg.io/docs/devel/release_notes/v1.30/,
  high). The operator updates automatically, so a routine bump could end backups with no
  warning. The owner chose the plugin (2026-10-03).
- The field still exists in the installed 1.30.1 (read), and `aws-k3s` uses it (read). That
  precedent is a template for the schedule and retention, not for the method.
- The plugin needs a controller and its CRDs. It is not installed (read). cert-manager, which
  it needs, is present (read).

**Shape** (docs, medium, to be checked against the plugin docs when writing the manifests):

- An `ObjectStore` resource (`barmancloud.cnpg.io/v1`) with the destination path and the
  credential settings.
- On the `Cluster`: `spec.plugins` with the plugin name, `isWALArchiver: true` and the object
  store name.
- A `ScheduledBackup` with `method: plugin`.
- Restore test: a new scratch `Cluster` with `bootstrap.recovery` from the object store, and
  no archiving of its own, so it never writes into the source's path.

**Safety copy**: take a `pg_dumpall` from the primary before any migration and keep it with
the backup. The docs show `pg_dump`, so `pg_dumpall` is an inference (docs, medium).

**Alternatives considered**: The in-tree method (above). Velero on the database volume,
rejected because a file copy of a running database is not consistent.

## 6. Volume backups

**Decision**: Velero, as the owner chose, with file-system backup (Kopia) to the existing bucket
under its own prefix. Same chart and shape as `aws-k3s` (read), with these settings:

| Setting | Value | Why |
|---|---|---|
| `deployNodeAgent` | true | file-system backup needs it (docs, high) |
| `configuration.uploaderType` | `kopia` | the proven choice on `aws-k3s` |
| `snapshotsEnabled` | false | the storage driver has no snapshots (docs, high; read, no snapshot CRDs) |
| `defaultVolumesToFsBackup` | true, with namespaces listed | as `aws-k3s` |
| node-agent memory limit | 1 GiB | Kopia needs 250 MB to over 1 GB, depending on file count (docs, medium) |
| repository password | own Secret, set before the first backup | the default is public, and changing it later loses access to existing backups (docs, high) |

**Do not back up the database volumes with Velero.** The database operator backs them up
consistently. `aws-k3s` already excludes the Matrix database for this reason.

**Volumes that need care**:

- CouchDB: its files are append-only and the vendor documents live copying as safe, with
  indexes copied before shards (docs, medium).
- Prometheus: the live time-series directory is not guaranteed consistent. Either use its
  snapshot API (needs the admin API enabled) or rely on the write-ahead log to recover a
  crash-consistent copy (docs, medium). The restore test decides which.
- Grafana and ntfy: SQLite. Scaling to zero for the backup removes the torn-write risk.
- Minecraft world and Grafana (scaled to zero): Velero backs up only volumes that a pod
  mounts. A volume with no pod is skipped (docs, medium-high). They need a short-lived
  staging pod, and the world is not safe to copy while the game runs.

**Credentials**: web identity (IRSA), as the owner chose. The Hetzner cluster already runs the
pod-identity webhook and has a self-hosted issuer, and the previous cluster ran Velero this way
(read). See section 7.

**Restore test**: `velero restore create --from-backup X --namespace-mappings live:scratch`
rebuilds the volume in a scratch namespace and leaves the live volume untouched (docs,
medium-high). Remove the scratch namespace afterwards.

**Known issues to plan around** (docs, medium): restores that stall near 97%, node-agent
out-of-memory kills, and an init container blocked by restrictive volume ownership.

**Alternatives considered**: Hetzner volume snapshots, which do not exist for volumes. A Hetzner
server snapshot, which captures only the root disk. Restic through Velero, which is the older
engine.

## 7. Backup storage and credentials

**Decision**: Use web identity (IRSA) for both Velero and the database backups, through the
issuer and webhook the cluster already has. No static key, no sidecar, and no change to the
control plane.

**What already exists** (read, 2026-10-03):

- The API server's issuer is `https://s3.eu-west-1.amazonaws.com/hetzner-k8s-irsa`. Its
  discovery document and keys are published to that public S3 location by the Terraform module
  `hetzner_irsa` (`main/hetzner_irsa.tf` in the `terraform` repository).
- The `pod-identity-webhook` runs in `kube-system` and injects the token and role ARN into pods
  whose service account carries the `eks.amazonaws.com/role-arn` annotation.
- The `shared-postgres` service account in `matrix` is already annotated with the role
  `hetzner-cnpg-restore-irsa`, which has read access to the old Matrix backups. This is the
  working proof that the path functions end to end.
- The `aws-k3s` Velero setup used IRSA too (read: its HelmRelease), with Kopia file backups.

An earlier draft of this document said the cluster had no IRSA and proposed IAM Roles Anywhere
for Velero, and a new issuer for the databases. That was wrong: it came from reading a stale
scratch clone of the Terraform repository.

**What to add**:

| Piece | Where | Detail |
|---|---|---|
| Velero role | `terraform`, new `main/hetzner_backups.tf` | an `irsa_role` for `velero:velero`, with the policy of `k3s_velero` limited to `velero-hetzner/*` and prefix-conditioned list actions |
| Database backup roles | same file | one `irsa_role` each for `matrix:shared-postgres` and `ente:ente-db` (the module trusts one service account per role), each limited to its own prefix (`cnpg-hetzner/shared-postgres`, `cnpg-hetzner/ente-db`) |
| Bucket policy | `terraform`, `main/iam_policies.tf` | add the two roles to the exemption from the IP-restriction deny |
| Velero service account | `home-cluster` | annotated with the Velero role ARN, no credential Secret |
| Database service accounts | `home-cluster` | annotated with the database backup role ARN. `shared-postgres` today uses the read-only restore role, so its annotation changes to the new role, which also needs read access to the old prefix until the restore source is no longer needed |

**Unproven** (docs, from a research sub-agent; medium):

- The Kopia uploader in the node-agent gets credentials once, through the SDK's chain, and
  hands the resulting key and session token to Kopia. It is not shown to refresh them during a
  running upload. IRSA sessions last one hour: the SDK requests the default duration, so a
  longer role maximum does not extend them (corrected 2026-10-03; an earlier draft said it
  would). The volumes here are small, so an hour is likely enough. The rehearsal uploads a large
  volume to find out, and the fallback is to split large volumes across runs.
- Whether the Velero node-agent pods get the token injected. They need the annotation on the
  node-agent service account as well as the server's. Rehearsal.

**Dependency**: the changes are in the `terraform` repository (CodeCommit), which is a different
clone from the scratch copy used earlier. Pull it, and run a plan, before editing.

**Alternatives considered**:

- IAM Roles Anywhere for Velero, the owner's first request. It needs a credential-helper sidecar
  on the Velero server and on every node-agent pod, and the chart has no sidecar value, so it
  would need Flux post-renderers. Its Kopia credential behaviour is unproven too. Dropped once
  IRSA was found to be present and proven (owner's decision, 2026-10-03). Roles Anywhere stays in
  use for DNS.
- Exposing the Roles Anywhere helper over the network for the databases. Rejected: it binds to
  the loopback by design, and anything that could reach it would get the credentials.
- Static IAM keys. Rejected by FR-016. A prefix-scoped key is the stop-and-ask fallback.
- Backblaze B2 instead of the AWS bucket. Not asked for, and it would not remove the credential
  question.

## 8. Migration of non-database volumes

**Decision**: A one-off copy job per volume, with the workload scaled to zero, from the old
volume to a new encrypted volume. Velero is used for backups and restore tests, not for the
migration.

**Rationale**:

- A Velero restore recreates the claim itself. Restoring into a pre-created claim is not
  documented as supported (docs, low). Restoring into the live namespace also conflicts with
  the objects Flux manages. The storage class mapping through a `change-storage-class`
  ConfigMap does work (docs, high), but it fits "restore elsewhere", not "swap in place".
- With the workload scaled to zero, a copy is consistent by construction. Data totals under 5
  GiB, so the downtime per service is minutes.

**Mechanics that need rehearsal**:

- Prometheus and Alertmanager are StatefulSets whose claim templates are immutable. The old
  set must be deleted with `--cascade=orphan`, the encrypted claim pre-created under the same
  name with the copied data, and the Helm values updated so that Flux recreates it.
- Synapse media is a stand-alone claim created by the chart. Changing its class means a new
  claim and a chart value that points at it.
- `couchdb`, `ntfy`, `grafana` and the Minecraft world are Deployments with a named claim.

**Alternatives considered**: Velero restore with the class mapping, as the migration step.
Rejected for the reasons above, and kept as the restore-test mechanism.

## 8b. Minecraft world backups

The world is the one volume whose damage can be deliberate and quiet, so it gets its own
schedule, frequency and retention (spec US8, FR-017 to FR-020).

**Decision**:

| Piece | Choice |
|---|---|
| Frequency | every 2 hours while the server runs, plus once after the last player leaves |
| Retention (tiers) | every 2 hours for 3 days, daily for 90 days, weekly for 1 year |
| Mechanism | three Velero schedules with different TTLs, or one schedule plus policy, to be settled in tasks. Kopia stores only changed data, so long retention is cheap |
| Clean copy | before the copy, `save-off` then `save-all flush` over RCON. After it, `save-on`. Velero backup hooks run these inside the server container (docs, medium-high) |
| End of session | the proxy creates a Velero backup of the namespace, waits for it to complete or for a limit, then scales the server to zero |
| Inspecting an old point | restore a chosen backup into a scratch namespace with a namespace mapping, leaving the live world alone (docs, medium-high) |

**Evidence and gaps**:

- Velero backs up only volumes that a running pod mounts, and skips the rest (docs,
  medium-high). That is why the end-of-session backup runs while the pod still exists, before
  the scale-down, and why no staging pod is needed for ongoing coverage.
- The server image is built in this repository (`pkgs/create-arkana-aeronautics-server`). It
  sets `enable-rcon=false`, has no RCON client, and runs the server from `entrypoint.sh`
  (read). A clean live backup needs an image change: enable RCON on the loopback with a
  password from a Secret, and add an RCON client such as `mcrcon`. That is a new image tag.
- The proxy is the owner's own Rust project (`mc-limbo-proxy`). Its idle watcher calls a
  scale-to-zero after `IDLE_TIMEOUT` (default 10 minutes) with no active players (read). The
  end-of-session backup goes before that call, and the proxy needs a Role to create and read
  Velero `Backup` resources. Its current Role allows only the scale subresource (read). On a
  timeout or failure it logs loudly and scales anyway, so a failed backup never leaves the
  server running at cost.
- Whether a save pause visibly hitches the game is not known. The first live test measures it.

**Why not a plain volume copy while running**: region files are written in place, so a copy mid
write can leave torn chunks. The save-and-flush sequence is the standard way to avoid that.

**Why a long tail matters**: a grief found weeks later is only recoverable from a backup older
than the grief. The tiers keep thin points far back without paying for every 2 hour copy for a
year.

## 9. Default StorageClass

**Decision**: Flip the default only after the throwaway-volume test and the first real
migration pass. Do it by editing the chart values: the old class loses `defaultStorageClass`, the
encrypted one gains it. Two defaults are ambiguous, so the change is one commit.

**Note**: Every manifest in `home-cluster/clusters/hetzner` names `hcloud-volumes` explicitly, so
flipping the default alone encrypts nothing that exists. It protects future volumes.
Migrations update each manifest to name the encrypted class.

## 10. Verification and rehearsal

**Decision**: One verification script that follows `contracts/verification.md`, with a test per
check. Run the whole procedure on a scratch database cluster and a scratch volume before the
first real migration, including the missing-Secret case. The script runs from a directory with
its own flake and a dev shell, so no tool is assumed on `PATH` (constitution IV).

## 11. Open points

1. **Kopia credential refresh** during a long upload is unproven. IRSA sessions last one hour.
   The rehearsal uploads a large volume, and the fallback is to split large volumes across runs.
2. **Node-agent token injection**: confirm the webhook injects into the node-agent DaemonSet's
   pods.
3. **The `shared-postgres` role swap**: resolved. The new role merges in the read statements of
   the old restore role (`include_restore`), so it keeps reading the old Matrix backups.
   Separately, `matrix/cnpg-restore-aws-creds` is not a long-lived key: it holds temporary
   credentials (a session token) from 2026-09-13 that nothing references. It is deleted, and there
   is no IAM key to revoke.
4. **Minecraft end-of-session backup** needs changes in three places: the server image in this
   repository, the cluster manifests in `home-cluster`, and the `mc-limbo-proxy` repository.
5. The IAM and bucket-policy changes are in a repository this feature does not own. They are
   the first tasks and block all backups.
