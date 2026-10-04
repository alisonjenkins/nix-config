---

description: "Task list for encrypting the household's data volumes on the Hetzner cluster"
---

# Tasks: Encrypt the household's data volumes on the Hetzner cluster

**Input**: Design documents from `/specs/004-hetzner-encrypted-volumes/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/verification.md, quickstart.md

**Tests**: Included. Constitution principle II requires test-first for the verification script and
proof by rehearsal before every live step. Infrastructure tasks are proven by the quickstart
scenarios named in each phase.

**Organization**: Grouped by user story. Phases 1 and 2 block every story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task).
- **[Story]**: the user story from `spec.md` (US1 to US8).
- **[CONSENT]**: changes live state. The owner must say yes to that specific step first
  (constitution III). Never batch consent.
- Each task is one commit (constitution I): reverting it alone leaves manifests that still
  build. Commit messages carry no AI attribution.

## Path conventions

Four repositories. Paths are prefixed with the repository:

- `nix-config:` this repository (this worktree: `.claude/worktrees/design-hetzner`).
- `home-cluster:` `~/git/home-cluster`, manifests under `clusters/hetzner/flux-system/`.
- `terraform:` `~/git/terraform` (the real clone; the scratch clone `~/git/terraform-plan-check`
  is stale and MUST NOT be used).
- `mc-limbo-proxy:` `~/git/personal/mc-limbo-proxy`.

Cluster commands assume `export KUBECONFIG=~/.kube/hetzner-cp.yaml`. Times are ISO 8601 UTC.
Never print a secret value, and never paste one into a task or a commit.

---

## Phase 1: Setup

**Purpose**: Branches, the record of the decision, and the verification script's scaffold.

- [ ] T001 Create one branch per repository for this feature: `nix-config:` (continue on `docs/hetzner-inplace-patching`), `home-cluster:` worktree `.claude/worktrees/enc-volumes` on `feat/hetzner-encrypted-volumes` off `origin/main`, `terraform:` branch `feat/hetzner-backup-irsa` off an up-to-date `master` (`git pull` first), `mc-limbo-proxy:` branch `feat/backup-before-scale`.
- [ ] T002 [P] Write `nix-config:docs/adr/0022-encrypt-hetzner-volumes.md` in the README template (Context, Decision, Alternatives rejected, Consequences, Evidence, Revisit when) covering: LUKS StorageClass, silent-plaintext risk, IRSA for both backup paths, plugin over in-tree, copy job over Velero restore, removal as soon as verified. Add its row to `nix-config:docs/adr/README.md` under "Hetzner cluster". Status: Proposed.
- [ ] T003 [P] Scaffold `nix-config:scripts/hetzner-volume-verify/flake.nix` with a `devShells.default` providing `kubectl`, `jq`, `cryptsetup`, `bats`, `coreutils`, `rsync`, `awscli2` and `shellcheck`, plus `README.md` pointing at `specs/004-hetzner-encrypted-volumes/contracts/verification.md`. Tools resolve from Nix, never `PATH` (constitution IV).
- [x] T004 [P] In `terraform:` run `tofu init` and `tofu plan` on `main/` and record that the baseline plan is empty (read-only). Read `main/hetzner_irsa.tf`, `main/modules/irsa_role/`, `main/k3s_velero_backup.tf` and `main/iam_policies.tf`, and note in `nix-config:specs/004-hetzner-encrypted-volumes/evidence/baseline.md` the module inputs the new roles need.

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: Credentials, the Postgres network fix, secrets, the verification script, and the
proven encrypted storage class. Nothing in phases 3 to 10 starts before this passes, except
that tasks inside this phase marked [P] may overlap.

### AWS side

- [x] T005 [P] In `terraform:main/hetzner_backups.tf` add one `irsa_role` per backup identity from a single map (Velero `velero:velero`, `matrix:shared-postgres`, `ente:ente-db`) on `module.hetzner_irsa.oidc_issuer`, each with a policy of the actions and shape of `k3s_velero` and `k3s_cnpg_backup` limited to its own prefix (`velero-hetzner`, `cnpg-hetzner/shared-postgres`, `cnpg-hetzner/ente-db`) with prefix-conditioned list actions. The module trusts one service account per role, so there are three roles, not one shared database role. Done on the `feat/hetzner-backup-irsa` branch of the Terraform repository. No longer session duration is set: the SDK requests the default one hour whatever the role's maximum is.
- [x] T006 Done within T005: `matrix:shared-postgres` keeps read access to the old restore prefix through `include_restore`, which merges the read statements of `hetzner_cnpg_restore` into its policy. In the `tofu plan` for T008 confirm its policy lists both its own prefix and the old one, and that `ente-db` gets only its own.
- [x] T007 In `terraform:main/iam_policies.tf` add the three new role ARNs to the `StringNotLike` principal exemption of `backups_s3_bucket_policy`, so they are not blocked by the IP-restriction deny.
- [x] T008 [CONSENT] Show the owner the `tofu plan` output for T005 to T007. It must add only the three roles, their policies and the bucket-policy change. After the owner approves, `tofu apply`. Record the plan summary and the three role ARNs in `nix-config:specs/004-hetzner-encrypted-volumes/evidence/aws.md`.
- [x] T008a [CONSENT] Fix the backup role policy found by probing it (2026-10-04). With the roles of T005 applied, `barman-cloud-check-wal-archive` run from a pod with the new role failed with `HeadBucket: 403 Forbidden`, and `ListBucketMultipartUploads` was denied even with the role's own prefix: the policy would have broken WAL archiving on the live database. The fix is committed on the Terraform branch `feat/hetzner-backup-irsa` (`ad39500`): `s3:ListBucket` uses `StringLikeIfExists` on `s3:prefix` (a `HeadBucket` request carries no prefix key), and `s3:ListBucketMultipartUploads` moves to its own unconditioned statement (it does not support the `s3:prefix` key). The owner runs a targeted `tofu plan` and `apply` on `module.hetzner_backup_irsa` and `aws_iam_role_policy.hetzner_backup` (the plan must show only the three policies changing). Then repeat the probe (a scratch pod in `matrix` with the `shared-postgres` ServiceAccount, the new role in `AWS_ROLE_ARN`, and a projected `sts.amazonaws.com` token): `HeadBucket` and `ListMultipartUploads` must work, and root listing and every other prefix must stay denied. The probe's first run left one incomplete multipart upload at `cnpg-hetzner/shared-postgres/_iam-probe/mpu.bin`: list and abort it once the policy allows it. Record the result in `evidence/aws.md`. Needed before T031.

### Cluster network and secrets

- [x] T009 [P] In `home-cluster:clusters/hetzner/flux-system/matrix/network-policies.yaml` extend `postgres-policy` (research §4): ingress to 8000 from the `cnpg-system` namespace, ingress to 5432 and 8000 from pods labelled `cnpg.io/cluster: shared-postgres`, ingress to 9187 from the `monitoring` namespace; egress to the same cluster label on 5432 and 8000. Keep every existing rule.
- [x] T010 [P] In `home-cluster:clusters/hetzner/flux-system/ente/netpol.yaml` check the `ente-db` policy for the same four needs (operator 8000, instance to instance 5432 and 8000, metrics, egress to itself) and add whatever is missing.
- [x] T011 [CONSENT] Open a pull request for T009 and T010, get the owner's approval, merge, and let Flux apply. Then confirm `kubectl get clusters.postgresql.cnpg.io -A` shows `shared-postgres` healthy with no `Instance Status Extraction Error` (quickstart A1). If it does not clear, stop and investigate before continuing.
- [x] T012 [P] Generate the volume passphrase with a cryptographically secure generator, without printing it, and write `home-cluster:clusters/hetzner/flux-system/secrets/hcloud-volume-passphrase.enc.yaml` (SOPS, key `encryption-passphrase`, namespace `kube-system`). Register it in `home-cluster:clusters/hetzner/flux-system/secrets/kustomization.yaml`. The owner stores the same value in the password manager (use `op` with the owner's approval; never echo the value). Confirm both copies hash equal.
- [x] T013 [P] Generate the Velero repository password the same way and write `home-cluster:clusters/hetzner/flux-system/secrets/velero-repo-credentials.enc.yaml` (namespace `velero`, key `repository-password`). The owner stores a copy in the password manager. It must exist before the first Velero backup, and changing it later loses access to the backups. Done 2026-10-04 with the namespace (PR 1566). Copy in the password manager done 2026-10-04.

### Verification script, test first

- [x] T014 Write `nix-config:scripts/hetzner-volume-verify/tests/verify.bats` first, with stubbed `kubectl`, `cryptsetup` and `lsblk`. One test per rule in `contracts/verification.md`: part 0 passes only for `crypto_LUKS` with an active mapping and fails for a plain filesystem and for a missing or empty Secret; part 1 data comparison passes on identical row counts and checksums and fails on one differing row or file; part 2 health fails on a restart since the switch; part 3 functional fails per service and fails with a clear message when the test-account credentials (`verify-bot` and the photo test account) are not in the environment; part 4 fails with no completed backup; the output format has one line per check and a final `verdict=verified` or `verdict=failed`; the exit code is non-zero on failure. Run it and confirm every test fails (red).
- [x] T015 Implement `nix-config:scripts/hetzner-volume-verify/verify.sh` (`--volume` and `--checks`, then the options of each check: see its usage text) until `tests/verify.bats` passes. Errors name the failing operation and its inputs. `shellcheck` clean.
- [ ] T016 [CONSENT] Create the dedicated test accounts the functional checks need (spec FR-006). Matrix: a low-privilege user `verify-bot` created through the authentication service, in a private, unencrypted test room that holds no household content. Photo service: a separate test account with a small test album. Store their credentials as SOPS secrets `home-cluster:clusters/hetzner/flux-system/secrets/verify-bot.enc.yaml` (namespace `matrix`) and `home-cluster:clusters/hetzner/flux-system/secrets/verify-photos-test.enc.yaml` (namespace `ente`), and register both in `secrets/kustomization.yaml`. `verify.sh` reads them from the environment and never prints them. Document how to export them in `nix-config:scripts/hetzner-volume-verify/README.md`.
- [x] T017 [P] Write `nix-config:scripts/hetzner-volume-verify/tests/guard.bats`, then implement `retain-pv.sh` (sets a PV's reclaim policy to `Retain` and refuses if the PV is unknown) and `destroy-old-volume.sh` (refuses unless the verification verdict is `verified`, a fresh backup is listed, and the PV is `Retain`; it then deletes the claim and the PV, and removes the volume at Hetzner). Tests first, then code (spec FR-007).
- [x] T018 [P] Write `nix-config:docs/hetzner-encrypted-volumes-rollback.md`, the way back before an old volume is removed (spec FR-010). Databases: promote the old instance again, destroy the new instance and its claim, set `storageClass` back, and confirm the old instance is primary and the apps reconnected. File volumes: scale the service to zero, repoint its manifest to the old claim, scale up, and verify. State the rule: it applies only while the old volume exists, and after removal the way back is the backup.
- [x] T019 [P] Write `nix-config:scripts/hetzner-volume-verify/tests/no-call.bats` first (stubbed metrics endpoint): `check-no-call.sh` prints `calls=N`, exits 0 only when the SFU reports 0 participants, exits non-zero for any participant, and exits non-zero (fail closed) when the endpoint is unreachable. Confirm it fails.
- [x] T020 Implement `nix-config:scripts/hetzner-volume-verify/check-no-call.sh` until `T019` passes. Read the SFU's `/metrics` on port 6789 (through `kubectl port-forward` to `matrix-stack-matrix-rtc-sfu`) and first confirm the exact participant metric name by reading the live output. Spec FR-009 and FR-006 use it before every step that interrupts chat.
- [x] T021 [P] Measure and budget memory on the master before adding load, and record it in `nix-config:specs/004-hetzner-encrypted-volumes/evidence/capacity.md` (read-only). Record `kubectl top node` and per-pod use now (76% of 7.9 GB). Estimate the added load: a second Postgres instance (up to its 1 GiB limit), the Velero server (512 MiB limit), the node-agent (1 GiB limit) and the plugin sidecars. Set explicit requests and limits for each. Define a stop threshold (for example node memory above 90%, or any swap-in) and a rule that backups and switchovers do not overlap. The 2026-09-29 outage came from memory pressure on this node.

### Encrypted storage class, proven

- [x] T022 In `home-cluster:clusters/hetzner/flux-system/hcloud-csi/helmrelease.yaml` set `storageClasses` to a list of two: `hcloud-volumes` (re-listed explicitly, `defaultStorageClass: true`, as today) and `hcloud-volumes-encrypted` (`defaultStorageClass: false`, `extraParameters` with `csi.storage.k8s.io/node-publish-secret-name` and `-namespace` pointing at the T012 Secret). Confirm in a `kustomize build` and `helm template` of the pinned chart that `volumeBindingMode: WaitForFirstConsumer` and `allowVolumeExpansion: true` are set on both.
- [x] T023 [CONSENT] Merge T022. Confirm `kubectl get sc` shows both classes, with only the old one default.
- [x] T024 [CONSENT] Prove it on a throwaway volume (quickstart B3). Apply a 1 GiB PVC and a pod in namespace `enc-test` using `hcloud-volumes-encrypted`. Run `verify.sh` part 0. Record the first-mount time against a plain volume (spec US5 scenario 3). Delete the namespace afterwards.
- [x] T025 [CONSENT] Missing-passphrase test (quickstart B4). Create a second, scratch StorageClass `hcloud-volumes-encrypted-test` in `enc-test` whose `node-publish-secret-name` points at a Secret that does not exist, and a throwaway volume on it. Never modify, rename or delete the real passphrase Secret in `kube-system`. Record whether the pod fails to start or the volume mounts as plain text. If it mounts as plain text silently, add a task to block it (a Kyverno policy that denies a PVC of the encrypted class unless its Secret exists) before any migration. Record the result in `nix-config:specs/004-hetzner-encrypted-volumes/evidence/storage.md`.
- [x] T026 [CONSENT] Online resize test on a throwaway encrypted volume (grow it while mounted). Record the result.
- [x] T025a [CONSENT] Block the silent plain-text case found in T025 (a Secret that exists but has no or an empty `encryption-passphrase`). In `home-cluster:clusters/hetzner/flux-system/kyverno/policies.yaml` add a `ClusterPolicy` that, on create of a `PersistentVolumeClaim` whose `storageClassName` is `hcloud-volumes-encrypted`, looks up `kube-system/hcloud-volume-passphrase` (an `apiCall`) and denies the claim unless `data."encryption-passphrase"` exists and is not empty. Set `validationFailureAction: Enforce` for this policy only. Test it on a throwaway claim in `enc-test`: a claim is admitted with the real Secret and denied against a scratch class and Secret with a wrong key (never touch the real Secret). Merge only with the owner's approval, then record the test in `evidence/storage.md`. Needed before T027 and before any migration.
- [x] T027 Needs T025a done. Record "storage proven" with its UTC time in `evidence/storage.md`. The 7 day clock starts when this and T049 are both done.

**Checkpoint**: both new roles apply, the Postgres status error is gone, the verification script and the no-call check pass their tests, the rollback runbook and memory budget exist, and the encrypted class is proven, including the missing-Secret case.

---

## Phase 3: User Story 1 - Every volume has a backup, and a restore is proven (Priority: P1)

**Goal**: Every volume has a backup stored away from it, and each restore is proven.

**Independent test**: Quickstart B1 and B2. A restore of each volume into a scratch space matches the source.

### Databases

- [x] T028 [US1] In `home-cluster:clusters/hetzner/flux-system/cnpg-barman-plugin/` add the Barman Cloud Plugin install (pinned version, its CRDs and controller), and register it in `home-cluster:clusters/hetzner/flux-system/flux-kustomizations/kustomization.yaml`. It needs cert-manager, which is present.
- [ ] T029 [US1] In `home-cluster:clusters/hetzner/flux-system/matrix/postgres/` add `objectstore.yaml` (an `ObjectStore` with `destinationPath: s3://ajj-backups/cnpg-hetzner/shared-postgres`, region `eu-west-1`, WAL and data compression, retention 14 days, credentials inherited from the IAM role). Edit `cluster.yaml`: add `spec.plugins` (barman-cloud plugin, `isWALArchiver: true`, the object store), and annotate the cluster's service account with the T006 role ARN through `serviceAccountTemplate`, keeping the region environment variables from the `aws-k3s` setup. Exclude the database volume from Velero with `inheritedMetadata` annotation `backup.velero.io/backup-volumes-excludes: pgdata`.
- [ ] T030 [US1] In `home-cluster:clusters/hetzner/flux-system/matrix/postgres/scheduledbackup.yaml` add a daily `ScheduledBackup` with `method: plugin` and the plugin's name, offset from the Velero schedule. Register the new files in the directory's `kustomization.yaml`.
- [ ] T031 [US1] [CONSENT] Needs T008a done. Before merging, run `check-no-call.sh`: it must print `calls=0`, otherwise wait. The change adds a plugin and a service account template to the live `Cluster`, which is expected to restart the primary (the 2026-10-03 network-policy change restarted it for about 2 minutes and crash-looped the authentication service). Merge T028 to T030 in a weekday daytime window. Wait for the plugin pods, then confirm a first base backup completes and WAL archiving is current (`kubectl cnpg status shared-postgres -n matrix`). Capture the evidence in `evidence/backups.md`.
- [ ] T032 [US1] Convert the photo database from its existing in-tree backup to the plugin. `ente-db` already has a working in-tree backup (daily since 2026-09-04, WAL archiving, 30 day retention, a Hetzner Object Storage bucket, the static `ente-s3` key), so this is a replacement of a working backup, not a first backup: do it only after T035 has proved the plugin and a restore on `shared-postgres`. First take an on-demand in-tree `Backup` and a fresh encrypted dump (T034 method). Then in `home-cluster:clusters/hetzner/flux-system/ente/`: add `objectstore.yaml` (destination `s3://ajj-backups/cnpg-hetzner/ente-db`, role `hetzner-cnpg-backup-ente-db-irsa`), in `db.yaml` replace `spec.backup.barmanObjectStore` with `spec.plugins` (CloudNativePG may refuse both at once: check with a server-side dry-run), annotate the service account, add the `pgdata` Velero exclusion, add an `externalClusters` entry for the old bucket so the old backups stay restorable, and switch `ente-db-daily` to `method: plugin`. Nothing prunes the old bucket once the in-tree config is gone: keep it until the new chain is restore-tested.
- [ ] T033 [US1] [CONSENT] Merge T032 in a weekday daytime window: `ente-db` restarts and Museum reconnects, and the photo service does not depend on the SFU, so no call gate is needed. Confirm the first plugin base backup completes and WAL archiving is current, restore-test it (as T035 does for `shared-postgres`), and confirm the cluster is healthy. Record in `evidence/backups.md`. Removing the old bucket and the `ente-s3` reference used for backups (Museum still needs `ente-s3` for photo storage) is a later step, after the restore test.
- [x] T034 [US1] [CONSENT] Take the safety dump: `kubectl exec` into the `shared-postgres` primary and stream `pg_dumpall` through `age` (the owner's public key from `.sops.yaml`) into `~/hetzner-encrypted-volumes/dumps/<utc-timestamp>-shared-postgres.sql.age`. The dump is never written in plain text. Do the same for `ente-db`. Record file names and sizes in `evidence/backups.md`, and note that the files are deleted once the last migration is verified.
- [ ] T035 [US1] [CONSENT] Database restore test (quickstart B2). Create namespace `scratch-restore` and a scratch `Cluster` that bootstraps by recovery from the `shared-postgres` backup, with no backup section of its own. Run `verify.sh --database` comparing the four databases (`niks3`, `synapse`, `mas`, `app`) with the live cluster. Delete the namespace afterwards. Repeat for `ente-db`.
- [ ] T036 [US1] Confirm what `matrix/cnpg-restore-aws-creds` is, by key names and presence tests only, never values. Found 2026-10-03: it holds `ACCESS_KEY_ID` (20 bytes), `SECRET_ACCESS_KEY` (40) and a 932 byte `SESSION_TOKEN`, was created 2026-09-13, and no pod or manifest references it. That is one-off temporary credentials from a role session, already expired (sessions last at most 12 hours), not a long-lived key, so there is no IAM access key to revoke and no Terraform change is needed. Record this in `evidence/aws.md`.
- [ ] T037 [US1] [CONSENT] Delete the stale secret `matrix/cnpg-restore-aws-creds` (spec FR-016, SC-012). First confirm no pod mounts or references it (`kubectl get pods -A -o json | jq`), and that the scratch restore of T035 worked through IRSA. Then delete the Secret and confirm a second restore test still works. List the cluster's secrets afterwards and record in `evidence/aws.md` that no AWS credential secret for backups remains.

### Velero and the file volumes

- [x] T038 [US1] In `home-cluster:clusters/hetzner/flux-system/namespaces/velero.yaml` add the `velero` namespace and register it in `namespaces/kustomization.yaml`.
- [x] T039 [US1] Needs T021 done first. In `home-cluster:clusters/hetzner/flux-system/velero/` add `helmrepository.yaml`, `helmrelease.yaml` and `kustomization.yaml`, modelled on the `aws-k3s` Velero HelmRelease and with these differences: chart 12.x pinned, `snapshotsEnabled: false`, `deployNodeAgent: true`, `uploaderType: kopia`, `defaultVolumesToFsBackup: true`, backup location `prefix: velero-hetzner` in bucket `ajj-backups` region `eu-west-1`, `credentials.useSecret: false`, the server service account annotated with the T005 role ARN, the repository password Secret from T013 referenced, node-agent memory limit 1 GiB (sized against `T021`), and the `velero-plugin-for-aws` init container pinned. Register it in `flux-system/kustomization.yaml` and `flux-kustomizations/`.
- [ ] T040 [P] [US1] In `home-cluster:clusters/hetzner/flux-system/velero/helmrelease.yaml` add `schedules`: one daily schedule per namespace group, staggered at different hours, `ttl: 720h`, covering `couchdb`, `ntfy`, `monitoring` and `matrix` (the Synapse media volume only; the database volume is excluded by T029). The Minecraft schedules are in US8. Progress: couchdb, ntfy and monitoring schedules are live; the matrix schedule is shipped disabled until the shared-postgres pod carries the pgdata exclusion (enable it after T031).
- [x] T041 [US1] [CONSENT] Do not merge until T021 is done and `kubectl top node` shows memory below its stop threshold, and no database base backup is running (T021's no-overlap rule). Merge T038 to T040. Watch node memory while the first backup runs and stop if it passes the threshold. Confirm the backup location reports `Available`, the node-agent pods carry the injected token and role ARN (research §11 point 2), and one backup of the smallest volume completes (quickstart A2b, B1).
- [x] T042 [US1] Turn on metrics and alerts for backups. In `home-cluster:clusters/hetzner/flux-system/velero/helmrelease.yaml` enable the chart's `ServiceMonitor`. Add `home-cluster:clusters/hetzner/flux-system/monitoring/prometheusrule-backups.yaml` with alerts for: a Velero backup that failed, no successful backup per schedule within its interval plus margin (for the 2 hourly Minecraft schedule, 5 hours), a database base backup older than 26 hours, and stale or failing WAL archiving. First read each metric name from the live `/metrics` of Velero and the database pods, and use those exact names. Route through the existing Alertmanager to ntfy. The alerts judge each schedule's last success, not each volume's, because volumes of stopped services (Grafana, the Minecraft world when idle) are covered by their one-off backups, not by a daily run. Register the file in the monitoring `kustomization.yaml`.
- [ ] T043 [US1] [CONSENT] Merge `T042`, then prove each alert fires: make a throwaway backup fail on purpose in `enc-test` and confirm the notification reaches ntfy, then clear it. Record the evidence in `evidence/backups.md` (spec edge case: failures are reported loudly). Progress (2026-10-04): the Velero failure path and the delivery to ntfy are proved (evidence/backups.md), which also found and fixed a gap (validation failures); the database and staleness alerts are not yet exercised.
- [ ] T044 [US1] [CONSENT] Credential-refresh test (quickstart B1b). Create a throwaway 10 GiB volume filled with incompressible data in namespace `enc-test`, back it up, and watch for credential errors and for node memory (stop if `T021`'s threshold is reached). The IRSA session lasts one hour whatever the role's maximum is, because the SDK requests the default. If the backup fails near one hour, split large volumes across separate backup runs, or stop and ask. Record the figures in `evidence/backups.md`, then delete the throwaway.
- [x] T045 [P] [US1] Write `nix-config:scripts/hetzner-volume-verify/staging-pod.yaml`, a minimal pod template that mounts a named claim, with the annotation `backup.velero.io/backup-volumes`, for volumes whose workload is scaled to zero (Grafana now, and the Minecraft world before its migration).
- [ ] T046 [US1] [CONSENT] Restore tests for each file volume (quickstart B2). For each of `couchdb-data`, `ntfy-data`, `matrix-stack-synapse-media`, the Alertmanager volume and the Prometheus volume: run a Velero backup, restore it with `--namespace-mappings <ns>:scratch-<name>`, run `verify.sh --files` against the live volume, then delete the scratch namespace. Do them one at a time, and record each result. The Prometheus result decides between its snapshot API and crash-consistent copy (research §6). Progress (2026-10-04, evidence/backups.md): ntfy-data, couchdb-data, Alertmanager and Prometheus passed; matrix-stack-synapse-media is open until the shared-postgres pod carries the pgdata exclusion (T031); Grafana is T047. Prometheus: keep the crash-consistent copy. Run check-restored-pvcs.sh after every restore and before any restored pod runs.
- [ ] T047 [US1] [CONSENT] Restore tests for the two volumes with no pod. For `kube-prometheus-stack-grafana` and `minecraft-create-arkana-data`, start the T045 staging pod against the claim (these services are stopped, so one backup dated after the last change satisfies FR-015), back it up, restore into a scratch namespace, verify, and remove the staging pod. The world is large, so note the time it takes. Progress (2026-10-04, evidence/backups.md): kube-prometheus-stack-grafana backed up and restored byte for byte (598 files); minecraft-create-arkana-data remains.
- [ ] T048 [US1] Add a "backups" section to `evidence/backups.md` listing, per volume, the latest backup time (for a volume whose service is stopped, a backup dated after its last change, per FR-015) and the restore-test result, and check SC-004 and SC-009.
- [ ] T049 [US1] Record "backups proven" with its UTC time. The 7 day clock starts when this and T027 are both done.

**Checkpoint**: every volume has a restore-tested backup. This is the safety net, and no migration starts before it.

---

## Phase 4: User Story 2 - The chat database moves to encrypted storage while staying online (Priority: P1)

**Goal**: The Matrix and cache databases run on an encrypted volume with at most 2 minutes of interruption.

**Independent test**: Quickstart B5 and Phase C. `verify.sh` ends `verdict=verified` and the old volume is gone.

- [ ] T050 [US2] [CONSENT] Rehearse on a scratch `Cluster` in namespace `scratch-migrate` (quickstart B5): create it on `hcloud-volumes` with a little test data, change `storage.storageClass` to `hcloud-volumes-encrypted`, scale to 2 instances, wait for zero lag, `kubectl cnpg promote`, run `verify.sh`, `kubectl cnpg destroy` the old instance. Then rehearse the way back: promote the old instance again and destroy the new one, following `T018`. Record whether the webhook accepted the changed class, the interruption in seconds, and any flag that differed in 1.30.1 (research §3). Delete the namespace.
- [ ] T051 [US2] If T050 shows the webhook rejects a changed class, switch the plan to the replica-cluster fallback (research §3): write the decision into `research.md` and add the tasks to repoint Synapse, MAS and the niks3 DB URI. Otherwise record that the primary method is confirmed.
- [ ] T052 [US2] In `home-cluster:clusters/hetzner/flux-system/matrix/postgres/cluster.yaml` set `spec.storage.storageClass` to `hcloud-volumes-encrypted`. This only affects volumes created later.
- [ ] T053 [US2] [CONSENT] Merge T052. Then, in a window with no call active (weekday daytime), set `instances: 2` in `cluster.yaml` (a second commit and merge). Wait until the new instance is `Ready` with zero replication lag. Before scaling, run `check-no-call.sh` (it must report 0 participants) and confirm memory headroom against `T021`. Run `verify.sh` part 0 against the new volume to prove it is encrypted.
- [ ] T054 [US2] [CONSENT] Take a fresh safety dump (T034 method), and a fresh base backup. Run `check-no-call.sh` again immediately before the switch (it must report 0). Then switch over: `kubectl cnpg promote shared-postgres <new instance> -n matrix`. Time the interruption.
- [ ] T055 [US2] Run `verify.sh` once, with `--checks encryption,compare,health,functional,backup` (the full command is in quickstart Phase C), `--kind database` and `--db` listing all four databases: encryption of the new volume, data comparison of every database, service health (Synapse, MAS and niks3 reconnected, no restarts), the functional check (send and read a message, upload and download a file, open known media) and a completed backup after the switch (`--since` is the switch time). Pipe the output through `tee -a specs/004-hetzner-encrypted-volumes/evidence/verdict-shared-postgres-1.txt`: `destroy-old-volume.sh` reads that file as its `--verdict-file`, and judges by the last verdict line.
- [ ] T056 [US2] If the verdict is `failed`, follow the rollback runbook `T018` instead and stop. On `verdict=verified`, run `retain-pv.sh` on the old PV, take a fresh backup of the new volume, and record the result. This is the point where the way back changes from the old volume to the backup.
- [ ] T057 [US2] Within 24 hours of T055: set `instances: 1` in `cluster.yaml` and merge, then confirm with `kubectl cnpg status` that the operator removed the old instance (the primary stays) and that the old PV is `Released` and still `Retain`. `destroy-old-volume.sh` refuses while a pod still mounts the claim, so this comes first. Then run it for the old claim, PV and Hetzner volume (it tolerates a claim the operator already removed), and confirm the volume no longer exists at Hetzner. Record `old_removed_at`. Which instance the operator removes on scale-down is rehearsed in T050.
- [ ] T058 [US2] Update `evidence/migrations.md` with the migration run record for `shared-postgres-1` (fields in `data-model.md`).

**Checkpoint**: Matrix chat data and the niks3 database are encrypted. SC-001 (database part), SC-003 and SC-004 are met for the Matrix databases.

---

## Phase 5: User Story 3 - The old plain copy is removed as soon as the move is verified (Priority: P2)

**Goal**: No plaintext copy lingers, and none is destroyed before verification.

**Independent test**: Remove a claim before verification and see the volume survive. Remove it after verification and see it gone.

- [ ] T059 [US3] Prove the guard (spec US3 scenario 1): on a throwaway volume with `Retain` set, delete its claim and confirm the volume still exists. Run it through `destroy-old-volume.sh` with an unverified verdict and confirm it refuses. Then rehearse the file rollback from `T018` on a throwaway service: copy, switch, fail the verification on purpose, repoint to the old claim, and confirm the service works on the old claim with its data intact.
- [ ] T060 [US3] Add a "removal log" table to `evidence/migrations.md` with `old_removed_at` for every volume and a check against the 24 hour limit (SC-007). Update it as each volume completes.
- [ ] T061 [US3] After the last migration, list every Hetzner volume (`hcloud volume list`, or the API) and confirm none of the old plain volumes remains. Delete the encrypted safety dumps from T034 and record it.

---

## Phase 6: User Story 4 - Media moves to encrypted storage (Priority: P2)

**Goal**: The Synapse media volume is copied to an encrypted volume with no loss.

**Independent test**: File count and checksums match, and known media opens in the chat client.

- [ ] T062 [P] [US4] Write `nix-config:scripts/hetzner-volume-verify/migrate-files.sh` with `bats` tests first: given a service, an old claim and a new claim, it checks the service is scaled to zero, runs a copy job (`rsync -a --checksum` between the two claims), and refuses to proceed if the exit status is non-zero. The copy job manifest template lives beside it as `copy-job.yaml`. Settle one gap here, before T065: `verify.sh`'s files comparison reads two local directories, and these volumes are in the cluster. The copy job's last step should build the path, size and checksum manifest of both claims inside the job pod, and `verify.sh` gains `--old-manifest` and `--new-manifest` to compare them (bats tests first).
- [ ] T063 [US4] Find how the Synapse media claim is defined: read the `matrix-stack` values in `home-cluster:clusters/hetzner/flux-system/matrix/helmrelease.yaml` for the media persistence setting, and record the setting name and how to point it at a new claim in `research.md` section 8. The claim is a stand-alone PVC created by the chart.
- [ ] T064 [US4] In `home-cluster:clusters/hetzner/flux-system/matrix/helmrelease.yaml` change the media storage to a new claim `matrix-stack-synapse-media-enc` of class `hcloud-volumes-encrypted` (the exact keys from T063), without applying it yet.
- [ ] T065 [US4] [CONSENT] In a no-call window, with `check-no-call.sh` reporting 0 immediately before scaling Synapse down: create the encrypted claim, scale Synapse (`matrix-stack-synapse-main`) to zero, run `migrate-files.sh`, then merge T064 and scale back up. Run `verify.sh --checks encryption,compare,health,functional,backup --kind files` (file counts and checksums, health, the known-media functional check, and a backup after the switch), with the output piped through `tee -a evidence/verdict-<volume>.txt` for `destroy-old-volume.sh`.
- [ ] T066 [US4] On `verdict=verified`: `retain-pv.sh`, a fresh Velero backup of the new media volume, then `destroy-old-volume.sh`. Record the run in `evidence/migrations.md`.

---

## Phase 7: User Story 5 - New volumes are encrypted by default (Priority: P2)

**Goal**: A volume created with no class gets encryption.

**Independent test**: Quickstart E1.

- [ ] T067 [US5] In `home-cluster:clusters/hetzner/flux-system/hcloud-csi/helmrelease.yaml` set `defaultStorageClass: false` on `hcloud-volumes` and `true` on `hcloud-volumes-encrypted`, in a single commit (two defaults at once are ambiguous). Do this only after T027, T049 and at least one verified migration (T055).
- [ ] T068 [US5] [CONSENT] Merge T067. Create a small volume naming no class, run `verify.sh` part 0 on it, then delete it. Confirm no existing workload restarted (`kubectl get pods -A` restart counts unchanged).
- [ ] T069 [P] [US5] Add a follow-up note to `evidence/storage.md`: once every volume is migrated, remove the explicit `storageClassName: hcloud-volumes` from the manifests so the default becomes the single source (constitution V). It is not done in this feature.

---

## Phase 8: User Story 6 - The passphrase cannot be lost (Priority: P2)

**Goal**: Either saved copy of the passphrase recovers the data.

**Independent test**: Quickstart E3.

- [ ] T070 [US6] [CONSENT] Recovery drill from the repository copy. Write test data to a throwaway encrypted volume, detach it, and attach it to a pod through a PV whose `nodePublishSecretRef` points at a Secret built from `sops -d` of `secrets/hcloud-volume-passphrase.enc.yaml`. Read the data back.
- [ ] T071 [US6] [CONSENT] Repeat T070 with a Secret built only from the password manager copy (the owner supplies it with `op`; never echo it). Both drills must read the data. Delete the throwaways, and record the results in `evidence/storage.md` (SC-006).

---

## Phase 9: User Story 7 - Every other household volume is encrypted as fast as is safe (Priority: P2)

**Goal**: Every remaining volume is encrypted within 7 days of the clock starting.

**Independent test**: Per volume, copy, verify, remove. Then list all volumes and find none on the old class.

Tasks T072 to T083 are independent per service and may run in parallel once US2 and US4 have shown the method.

- [ ] T072 [P] [US7] Photo database `ente-db`: the same procedure as US2 (tasks T050 to T058) with `home-cluster:clusters/hetzner/flux-system/ente/db.yaml`. Functional check: sign in and open a known album. Record the run.
- [ ] T073 [P] [US7] `couchdb-data`: in `home-cluster:clusters/hetzner/flux-system/couchdb/deployment.yaml` change the claim to an encrypted class claim (a new claim name), scale the service to zero, `migrate-files.sh`, scale up, `verify.sh --checks encryption,compare,health,functional,backup --kind files` (output teed to the verdict file). Functional check: read a known document and write a test document. Then `retain-pv.sh`, a fresh backup, `destroy-old-volume.sh`.
- [ ] T074 [P] [US7] `ntfy-data`: the same, with `home-cluster:clusters/hetzner/flux-system/ntfy/pvc.yaml`. Functional check: publish and receive a test notification.
- [ ] T075 [P] [US7] Alertmanager and Grafana: both are in `home-cluster:clusters/hetzner/flux-system/monitoring/helmrelease.yaml` (the storage lines for Alertmanager's claim template and Grafana's `storageClassName`). Grafana is scaled to zero, so its copy needs no pause. Functional check: Alertmanager lists its silences, Grafana loads its data sources.
- [ ] T076 [US7] Prometheus: its claim template is immutable. Scale it down through the operator, copy to a new encrypted claim with the exact name the StatefulSet expects, delete the StatefulSet with `--cascade=orphan`, update the storage class in `monitoring/helmrelease.yaml` and let Flux recreate it. Functional check: a query that spans the migration returns data on both sides. Copy the history (owner's decision).
- [ ] T077 [US7] Minecraft world: in `home-cluster:clusters/hetzner/flux-system/minecraft/create-arkana-pvc.yaml` change to an encrypted claim, copy with `migrate-files.sh` (the server is already scaled to zero, so the copy is consistent), then in a short session confirm the world loads (functional check), and scale back to zero. Then the same removal steps.
- [ ] T078 [US7] After each of T072 to T077, run `retain-pv.sh`, take the fresh backup, and run `destroy-old-volume.sh`, and add its row to `evidence/migrations.md`.
- [ ] T079 [US7] Confirm SC-008: list all claims with `kubectl get pvc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.storageClassName` and find none on `hcloud-volumes`, and no old plain volume at Hetzner.

---

## Phase 10: User Story 8 - The Minecraft world can be rolled back to before a grief (Priority: P2)

**Goal**: The world is backed up every 2 hours while it runs and after the last player leaves, in tiers up to a year, and any point restores to a scratch space.

**Independent test**: Quickstart F1 to F4. This phase does not gate the encryption deadline and runs beside phases 4 to 9.

### Server image (nix-config)

- [ ] T080 [US8] Write a test first (a `nix build` check or a shell test in `nix-config:pkgs/create-arkana-aeronautics-server/`) that the generated `server.properties` has RCON enabled on the loopback with a password read from an environment variable, and that the image contains an RCON client. Confirm it fails.
- [ ] T081 [US8] In `nix-config:pkgs/create-arkana-aeronautics-server/default.nix` change `enable-rcon=false` to enabled with the RCON port bound to the loopback only, add `mcrcon` to the image, and have `entrypoint.sh` write the password from the environment into the server's configuration at start. Run the T080 test until it passes, then `just check`.
- [ ] T082 [US8] Build and push the new image tag through the existing pipeline. Record the tag for T084.

### Cluster (home-cluster)

- [ ] T083 [P] [US8] Create a Secret `home-cluster:clusters/hetzner/flux-system/secrets/minecraft-rcon.enc.yaml` (namespace `minecraft`, key `rcon-password`) with a generated password, SOPS-encrypted, and register it. Never print the value.
- [ ] T084 [US8] In `home-cluster:clusters/hetzner/flux-system/minecraft/deployment.yaml` set the T082 image tag, add the RCON password environment variable from the T083 Secret, and add Velero hook annotations: `pre.hook.backup.velero.io/command` running `mcrcon` with `save-off` then `save-all flush`, and `post.hook.backup.velero.io/command` running `save-on`, each with a timeout and `on-error: Fail` for the pre-hook and `Continue` for the post-hook.
- [ ] T085 [US8] [CONSENT] Merge T084. In a short session with one player connected, run a backup and measure the save pause (quickstart F1). Record the hitch length and confirm no disconnect (FR-018). Adjust the timeouts if needed.
- [ ] T086 [P] [US8] In `home-cluster:clusters/hetzner/flux-system/velero/helmrelease.yaml` add three schedules for the namespace `minecraft`: every 2 hours with `ttl: 72h`, daily with `ttl: 2160h`, and weekly with `ttl: 8760h`. Label the backups so the three tiers can be listed and restored separately (FR-019).
- [ ] T087 [US8] [CONSENT] Merge T086 and confirm the first runs appear in `velero backup get` with the right TTLs. A run while the server is down backs up no volume, which is expected.

### Proxy (mc-limbo-proxy)

- [ ] T088 [US8] In `mc-limbo-proxy:` write tests first (cargo test, a fake Kubernetes API) for the new behaviour: before the idle watcher scales the backend to zero, it creates a Velero `Backup` for the namespace, polls its phase, scales to zero when it is `Completed`, and still scales to zero after the timeout or on a failure, logging an error with the backup name. Confirm they fail.
- [ ] T089 [US8] Implement it in `mc-limbo-proxy:src/idle.rs` and `src/k8s.rs` (a new `BackupController` beside `BackendController`), with a `BACKUP_TIMEOUT` setting in `src/config.rs` (default 10 minutes) and a `--no-backup` switch. `cargo fmt --check`, `cargo clippy -- -D warnings`, no `unwrap` outside tests (constitution IV).
- [ ] T090 [US8] In `home-cluster:clusters/hetzner/flux-system/minecraft/proxy-rbac.yaml` add a Role in the `velero` namespace allowing the proxy's service account to `create`, `get` and `list` `backups.velero.io`, with its RoleBinding. Add the new proxy image tag and `BACKUP_TIMEOUT` to `proxy-deployment.yaml`.
- [ ] T091 [US8] [CONSENT] Merge T090, let the last player leave, wait out the idle timeout, and confirm a backup dated after the last change exists and the server then scales to zero (quickstart F2). Also force a failure and confirm the server still scales to zero after the limit.

### Restore and tiers

- [ ] T092 [US8] Write `nix-config:scripts/hetzner-volume-verify/tests/check-world.bats` first, with a tiny fixture world: a valid region file passes with zero unreadable chunks; a region file with one chunk whose compressed data is truncated fails and names the file and the chunk coordinates; a region whose header points outside the file fails; an empty or missing `region/` directory fails. Confirm it fails.
- [ ] T093 [US8] Implement `nix-config:scripts/hetzner-volume-verify/check-world.sh` until `T092` passes. It walks `region/*.mca` (and each dimension's `region` directory), reads every chunk's header, decompresses the chunk and parses its NBT, and prints the number of chunks read and the number unreadable. It exits non-zero if any chunk is unreadable (spec FR-018). Add a Python with an NBT library to `scripts/hetzner-volume-verify/flake.nix`; tools come from the Nix dev shell.
- [ ] T094 [US8] [CONSENT] Restore an old point to a scratch namespace (quickstart F3): build something recognisable, wait for a backup, change it, restore that backup with a namespace mapping, run `check-world.sh` on the restored copy and require zero unreadable chunks, open the restored world, and repeat the check on one backup taken while a player was building, and confirm it holds the earlier state with no corrupted chunks and the live world is unchanged (SC-011).
- [ ] T095 [US8] Write `nix-config:docs/hetzner-minecraft-world-restore.md`, a short runbook: how to list the tiers, choose a point, restore it next to the live world, and compare. Check back after each tier has had time to appear (quickstart F4), and record the result.

---

## Phase 11: Polish and cross-cutting

- [ ] T096 [P] Record the leftovers that stay unencrypted (node root disks, `emptyDir` scratch such as the Postgres scratch and Synapse temp directories) in `nix-config:docs/adr/0022-encrypt-hetzner-volumes.md` with the owner's acceptance (spec FR-013), and offer memory-backed `emptyDir` where it fits.
- [ ] T097 [P] Replace the "Encryption of the Matrix volumes" section of `nix-config:docs/hetzner-inplace-patching-design.md` with a short pointer to this feature's spec, plan and research, so there is one source.
- [ ] T098 Update `nix-config:docs/adr/0022-encrypt-hetzner-volumes.md` with the final evidence (the results of T024 to T026, T044, T050 and T094), move its status to Accepted, and add the "Revisit when" conditions.
- [ ] T099 Re-run every quickstart scenario that has a pass condition, and tick SC-001 to SC-012 in `evidence/success-criteria.md` with the evidence for each. Clear any open item.
- [ ] T100 Delete leftover scratch resources (`enc-test`, `scratch-restore`, `scratch-migrate`, restore namespaces) and confirm `kubectl get ns` lists none of them.
- [ ] T101 Open the pull requests: one per repository, with the atomic commits intact. Each description says what changed, why, and the verification evidence. Merge by local rebase and fast-forward (constitution I).

---

## Dependencies and order

- **Phase 1 then Phase 2 then everything else.** Phase 2 blocks all stories.
- **Within Phase 2:** T005 to T008 (AWS) and T009 to T011 (network) and T012 to T013 (secrets) and T014 to T017 (script) are independent groups. T022 to T027 need T012.
- **Also in Phase 2:** the rollback runbook T018, the no-call check (T019, T020) and the memory budget T021 run beside the rest. T021 must finish before Velero is installed (T039) and before it is merged (T041). T020 must exist before the first step that interrupts chat (T031, T053, T054). The test accounts T016 must exist before the first functional check (T055).
- **US1 (Phase 3) before any migration.** It needs T008 (roles), T011 (policy), T013 (Velero password). Its checkpoint sets the 7 day clock together with T027. Within US1, the alerts (T042, T043) follow the first Velero backup, and the static-key removal (T036, T037) follows the database restore test.
- **US2 (Phase 4)** needs US1 and T050. **US4 (Phase 6)** and **US7 (Phase 9)** need US1 and T062. They do not depend on US2, so they can start once the rehearsal method is known.
- **US3 (Phase 5)** is the removal rule used by every migration. T017 and T059 come before the first removal.
- **US5 (Phase 7)** needs one verified migration. **US6 (Phase 8)** needs T024 only.
- **US8 (Phase 10)** needs T041 (Velero running). It does not depend on encryption and runs in parallel. Inside US8, the chunk checker (T092, T093) must exist before the old-point restore (T094).
- **Polish (Phase 11)** last.

## Parallel examples

- Phase 2: T005 and T009 and T012 and T014 together, in four repositories or files.
- Phase 3: T032 (photo database backup conversion, after T035) beside T038 to T040 (Velero install).
- After US1: US2, US4 and US7 together, as long as no two share a no-call window.
- Phase 9: T072 to T075 together; T076 and T077 separately because they are bigger.
- Phase 10: T080 to T082 (image), T083 and T086 (cluster), T088 and T089 (proxy) are three independent streams until T085.

## Implementation strategy

- **MVP**: Phases 1 and 2 and US1 and US2. That gives restore-tested backups for everything and an encrypted Matrix database, which is the most sensitive data, with the verification gate proven.
- **Then** US4 (media), US3 (guard) and US5 (default) for the rest of the Matrix data.
- **Then** US7 in parallel to meet the 7 day deadline, with US8 running beside it.
- **Stop rule**: if a rehearsal fails (T025, T044, T050), stop and decide with the owner. The deadline slips before a gate does.
- **Before the first live step** the owner reads T008 and T011, because they are the first two consent gates.

## Notes

- Total tasks: 101. Per story: US1 22, US2 9, US3 3, US4 5, US5 3, US6 2, US7 8, US8 16. Setup 4, Foundational 23, Polish 6. 28 tasks need consent.
- One commit per task; each repository's changes land in its own pull request.
