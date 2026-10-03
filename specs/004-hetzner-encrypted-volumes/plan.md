# Implementation Plan: Encrypt the household's data volumes on the Hetzner cluster

**Branch**: `docs/hetzner-inplace-patching` | **Date**: 2026-10-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-hetzner-encrypted-volumes/spec.md`

## Summary

Every household volume moves to a LUKS-encrypted Hetzner volume within 7 days, with a
restore-tested backup first and the old plain volume gone within 24 hours of a passed
verification. The Matrix data goes first.

The approach, from `research.md`:

1. Fix what blocks the database tooling: a Cilium policy stops the operator reaching the
   Postgres instances.
2. Give every volume a backup. Databases use the operator's Barman Cloud Plugin for continuous
   backups. Other volumes use Velero with Kopia file backups. Both write to the existing S3
   bucket under new prefixes, with short-lived credentials and no stored keys, through the web
   identity (IRSA) the cluster already has. The two new AWS roles are created in the
   cloud-account Terraform repository.
3. Add a second StorageClass that encrypts, prove it on a throwaway volume, and prove that a
   missing passphrase cannot silently produce a plain volume.
4. Move the databases by adding a replica on the encrypted class, switching over, verifying
   and destroying the old instance.
5. Move the file volumes by a copy job with the service scaled to zero.
6. Verify each move with one script, then make the encrypted class the default.
7. Back up the Minecraft world every 2 hours while it runs and once more after the last player
   leaves, keep the backups for up to a year in tiers, and restore any point to a scratch
   location. This needs a clean-save step in the server image and a backup step in the proxy.

## Technical Context

**Language/Version**: YAML for Flux and Kustomize manifests (home-cluster). HCL for Terraform
(cloud-account repository). Bash for the verification script (nix-config), run through a Nix
dev shell. Nix for the server image and the control-plane setting. Rust for the proxy change.

**Primary Dependencies**: Hetzner CSI driver v2.23.0 (`hcloud-csi` chart). CloudNativePG
operator 1.30.1 with PostgreSQL 17 and the Barman Cloud Plugin. Velero chart 12.x with the AWS
plugin and Kopia. The cluster's existing IRSA setup (pod-identity webhook and the
`hetzner-k8s-irsa` issuer). SOPS with age. Flux. Cilium with network policies. AWS S3 and IAM.
For the Minecraft world: an RCON client in the server image and a change to `mc-limbo-proxy`.

**Storage**: Hetzner Cloud volumes with LUKS (new). S3 bucket `ajj-backups` for backups.

**Testing**: A scratch database cluster and scratch volumes for rehearsals. `kustomize build`
and `yamllint` on every manifest change (home-cluster CI runs `yamllint`). `bats` for the
verification script with stubbed tools. `tofu plan` for the Terraform change. Restore tests into
scratch namespaces.

**Target Platform**: A single-node k3s cluster on Hetzner (`nbg1`), NixOS image.

**Project Type**: Infrastructure change across three repositories (see Project Structure).

**Performance Goals**: Database switch interruption at most 2 minutes (SC-003). Database
restore point within 5 minutes (SC-004).

**Constraints**: Steps that interrupt chat run weekday daytime with no call active (FR-009).
Everything encrypted within 7 days of the storage being proven (SC-008). Old plain volume
removed within 24 hours of a passed verification (SC-007). Backups cost only bucket storage.

**Scale/Scope**: Nine volumes, eight services, under 5 GiB of data in total.

Unknowns from the template are resolved in `research.md`. The unproven points are rehearsal
steps in Phase B, not assumptions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Result | How the plan meets it |
|---|---|---|
| I. Atomic, revertable history | Pass | One commit per task. Each repository's changes land through its own pull request. No squash, no AI attribution. A revert of any one commit leaves manifests that still build |
| II. Test first, evidence before done | Pass | The verification script has `bats` tests written first. Every migration prints its evidence. Manifests are built with `kustomize build` and `yamllint` before commit. Rehearsals precede every live step |
| III. IaC, live changes by consent | Pass, with consent gates | All changes are made in the repos and applied by Flux or `tofu`. The live steps that mutate the cluster are listed below as consent gates. Each needs the owner's explicit permission |
| IV. Errors carry context | Pass | The script's lines name the volume, the check and the input. Its tools come from a Nix dev shell, not `PATH` |
| V. Right altitude, single source | Pass, one note | The class name appears in each manifest. Migrations name the encrypted class explicitly. Once the default is flipped, removing the explicit names is a follow-up that makes the default the single source |
| VI. Record the why | Pass | ADR 0022 is written in the same pull request as the first change (the storage class and backup decisions, the silent-plaintext risk) |
| VII. Fork patches | Not applicable | No fork |

No violations, so Complexity Tracking is empty.

### Consent gates (principle III)

Each of these changes live state and needs the owner's explicit yes, one per step:

1. Applying the Terraform change (IAM and the bucket exemption).
2. Merging the home-cluster pull requests that Flux then applies, once per phase.
3. Creating the throwaway volume and the scratch database cluster.
4. Each database switchover and each scale-to-zero of a service.
5. Setting an old volume's reclaim policy to `Retain`, and destroying an old volume.
6. Flipping the default StorageClass.
7. Each Minecraft step that touches the running game: enabling RCON, the first save-pause test,
   and the proxy change that runs a backup before scale-down.

## Project Structure

### Documentation (this feature)

```text
specs/004-hetzner-encrypted-volumes/
├── plan.md                  # This file
├── research.md              # Phase 0: decisions, evidence, unproven points
├── data-model.md            # Phase 1: volume inventory, entities, state machine
├── quickstart.md            # Phase 1: how to prove each phase works
├── contracts/
│   └── verification.md      # Phase 1: the verification gate
├── checklists/
│   └── requirements.md      # spec quality checklist
└── tasks.md                 # Phase 2 (/speckit-tasks, not created here)
```

### Source code (three repositories)

```text
nix-config (this repository)
├── specs/004-hetzner-encrypted-volumes/        # above
├── docs/adr/0022-encrypt-hetzner-volumes.md    # the why, in the first PR
├── pkgs/create-arkana-aeronautics-server/      # RCON on loopback, an RCON client, new image tag
├── docs/hetzner-encrypted-volumes-rollback.md # the way back before an old volume is removed
├── docs/hetzner-minecraft-world-restore.md     # restoring an old world backup next to the live one
├── specs/004-hetzner-encrypted-volumes/evidence/   # the record of each rehearsal, backup and migration
└── scripts/hetzner-volume-verify/
    ├── flake.nix                               # dev shell: kubectl, jq, cryptsetup, bats, rsync, awscli
    ├── verify.sh                               # implements contracts/verification.md
    ├── check-no-call.sh                        # fails closed unless the SFU reports no participants
    ├── check-world.sh                          # reads every chunk of every region file, zero unreadable
    ├── migrate-files.sh, copy-job.yaml         # the copy job for file volumes
    ├── retain-pv.sh, destroy-old-volume.sh     # the removal guard
    ├── staging-pod.yaml                        # mounts a claim whose workload is scaled to zero
    └── tests/                                  # bats, written first, with stubbed tools

home-cluster (GitOps, clusters/hetzner/flux-system/)
├── hcloud-csi/helmrelease.yaml                 # second StorageClass, later the default flip
├── secrets/                                    # volume passphrase, backup keys, Velero repo password (SOPS)
├── velero/                                     # HelmRepository, HelmRelease (IRSA annotations on the server and
│                                               #   node-agent accounts), schedules incl. the Minecraft tiers
├── cnpg-barman-plugin/                         # the plugin controller and its CRDs
├── matrix/postgres/cluster.yaml                # plugin backup, then the migration to the new class
├── matrix/postgres/                            # extended Cilium policy for the operator and replication
├── matrix/postgres/scheduledbackup.yaml        # daily base backup (method: plugin)
├── monitoring/prometheusrule-backups.yaml      # alerts for failed and stale backups
├── ente/db.yaml                                # same changes for the photo database
├── minecraft/                                  # backup hook annotations, RCON Secret, proxy Role
└── couchdb/ ntfy/ monitoring/ matrix/          # the volume classes, per migration

terraform (cloud-account repository, CodeCommit; the real clone is ~/git/terraform)
└── main/
    ├── hetzner_backups.tf                      # two IRSA roles via the irsa_role module on the
    │                                           #   hetzner_irsa issuer, with policies for the two prefixes
    └── iam_policies.tf                         # exempt the new roles from the IP deny

mc-limbo-proxy (the owner's proxy repository)
└── src/                                        # create a Velero backup and wait, before scale-to-zero
```

**Structure Decision**: This is infrastructure in four existing repositories, not a new
application. The proxy repository only gains the end-of-session backup step. The specs, the decision record and the one script live in nix-config, which owns
the spec-kit setup. The cluster manifests live in home-cluster because Flux applies them. The
cloud permissions live in the Terraform repository because that is where the bucket is managed.

## Phases and order

Order is fixed by safety: backups, then proof, then data. The calendar assumes the owner
approves each consent gate promptly. Day 0 is the day the first Terraform change applies.

| Phase | Work | Gate to leave the phase | Days |
|---|---|---|---|
| A. Prerequisites | Terraform: two IRSA roles (Velero, database backups) and the bucket exemption. Decide the `shared-postgres` role swap. Extend the Postgres policies (operator, replication, metrics). Passphrase Secret, Velero repository password | `tofu plan` clean and applied. A test pod obtains temporary credentials by web identity for each new role. The Postgres status error clears | 0 to 2 |
| B. Prove the mechanisms | Install the Barman plugin and Velero with IRSA. Run the first backups, with a large upload to test credential refresh. Restore-test every volume. Add the encrypted class (non-default) and test it on a throwaway volume, including the missing-Secret case. Rehearse the database switch on a scratch cluster. Write `verify.sh` with its tests | SC-004 and SC-009 met. The silent-plaintext question answered. Rehearsal passes. **The 7 day period starts here** | 2 to 5 |
| C. Databases | Matrix and cache first, then the photo database. Each in a no-call window | Verification passes, fresh backup exists | days 1 to 2 of the 7 |
| D. File volumes | Media, document database, notification server, Alertmanager, Grafana, Prometheus, Minecraft world. Independent services move in parallel | Verification passes for each | days 1 to 5 of the 7 |
| E. Default and cleanup | Flip the default. Remove old volumes within 24 hours of each pass. List unencrypted leftovers (FR-013). Write the record | SC-005, SC-007 and SC-008 met | days 5 to 7 of the 7 |
| F. Minecraft backups | RCON and a client in the server image. Backup hooks and the tiered schedules. The proxy change. Test a restore of an old point to a scratch location | SC-010, SC-011 met, and a hitch measurement recorded | in parallel with C to E |

Phases C and D overlap where services are independent, which is how the 7 days are met. Phase F
runs beside them because it does not gate the encryption deadline. Phase A depends on a
repository this feature does not own. It sits before the 7 day period starts, as the spec's
Assumptions say.

## Risks and mitigations

| Risk | Effect | Mitigation |
|---|---|---|
| A missing passphrase silently gives a plain volume | Data believed encrypted is not | Secret created first. Verification part 0 checks the device. Rehearsal deletes the Secret on purpose |
| The Postgres policy blocks replication | A second instance never syncs | Fix it in Phase A and test with a scratch cluster |
| The webhook rejects a changed storage class | The primary method fails | Rehearsal first. Fallback is a second cluster in replica mode |
| A live file copy of a busy volume is inconsistent | A backup that cannot be restored | The restore test decides. The service is paused for the backup until it passes |
| Terraform lives in another repository and may be behind | An unexpected plan | Pull, plan and read the diff before applying |
| Seven days is short | A step is rushed | Gates do not move. If a gate fails, the deadline slips, not the check |
| Kopia does not refresh credentials during an upload | A long backup fails partway | Test with a large upload in Phase B. IRSA sessions last one hour, so large volumes are split across runs if needed |
| The Velero node-agent gets no token | Uploads fail with no credentials | Annotate the node-agent service account too, and test in Phase B |
| A save pause hitches the game | Players notice | Measure in the first live test. Move the interval if needed |
| The proxy's backup step hangs | The server runs at cost | A time limit, then scale anyway and log loudly |
| A backup fails or goes stale unnoticed | The safety net is gone when an old volume is removed | Alert rules for failed and stale Velero backups and database archiving, routed to ntfy, and proven by a deliberate failure |
| Memory pressure on the 8 GB master | Swap thrash slows the datastore, as on 2026-09-29 | Measure headroom first, set explicit limits, stop at a threshold, and never overlap backups and switchovers |
| A failed verification has no tested way back | Data stuck on the new volume | A rollback runbook, rehearsed for a database and for a file volume before the first real move |
| An interrupting step runs during a call | A call drops | A fail-closed check that the SFU reports no participants, run immediately before each step |
| A stale credential secret lingers | The no-keys requirement cannot be shown | `matrix/cnpg-restore-aws-creds` is expired temporary credentials, not a key. Delete it and record that no AWS credential secret for backups remains |
| Backups are the way back once old volumes are gone | A bad backup removes the safety net | Restore tests before any move. A fresh backup of the new volume before any removal |

## Post-design Constitution Check

Re-checked against `data-model.md`, `contracts/verification.md` and `research.md`. No principle
is bent. The one note under V stands: explicit class names are a deliberate choice for the
migration and are removed once the default is the encrypted class.

## Complexity Tracking

No violations to justify.
