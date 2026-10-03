# Specification Quality Checklist: Encrypt the household's data volumes on the Hetzner cluster

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-03
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Validated 2026-10-03 on the first pass; no iteration needed.
- The method (replication, a second storage setting, a retained reclaim policy, the specific
  operator and storage driver) is kept out of the spec and belongs in `plan.md`. The spec
  says "copy while the database stays in use" as the requirement.
- Defaults chosen from the design doc and open to `/speckit-clarify`: daily full backups (FR-004, FR-015),
  2 minute interruption (FR-005, SC-003), removal of the old volume within 24 hours of
  a passed verification (FR-007, FR-008, SC-007).
- Revised 2026-10-03 at the owner's request: all volumes are in scope up front, not deferred.
  The earlier 90 day deadline for the remaining volumes became 7 days after the encrypted
  storage is proven (FR-012, SC-008), confirmed by the owner. The owner also chose to copy
  monitoring history, not discard it, and confirmed the 5 second call freeze tolerance and the
  stop-and-ask rule for the cost ceiling in spec 003. Story 7 moved from P3 to P2, and FR-015 was added so the
  photo service database gets a restore-tested backup too.
- Two unproven points are carried as assumptions, each with a rehearsal in the plan: the
  encrypted storage method with the installed driver, and a changed storage setting on an
  existing database cluster.
- Ordering with `specs/003-hetzner-inplace-patching/`: this feature's Matrix work lands first,
  before the call machine is created.
- Confirmed by the owner on 2026-10-03: backups to lose at most 5 minutes (continuous archiving
  plus a daily full backup), stored in the existing AWS bucket, interrupting steps on weekday
  daytime, and this feature lands before spec 003.
- Changed 2026-10-03 at the owner's request: no fixed soak period. The old plain volume is
  removed within 24 hours of a passed verification (data comparison, health checks and a
  functional check). For a database a fresh backup must also exist. The media store and the
  other non-database volumes have no backup, so for them verification is the only safeguard.
- Changed 2026-10-03 at the owner's request: Velero backs up the volumes that have no backup,
  before anything moves. Story 1 now covers every volume (databases with continuous archiving,
  other volumes with a daily backup), FR-015 and SC-009 were added, and the earlier "no backup
  for non-database volumes" assumption was replaced. Velero is named only in Assumptions as the
  owner's choice. Two plan dependencies are recorded there: write access to the bucket from the
  Hetzner cluster, and file-level backup consistency without volume snapshots.
- Added 2026-10-03 at the owner's request: Minecraft world backups every 2 hours while running
  and after the last player leaves, kept in tiers for up to a year (story 8, FR-017 to FR-020,
  SC-010, SC-011), and short-lived backup credentials (FR-016, SC-012). The owner chose IAM Roles
  Anywhere for Velero, web identity for the databases, and the Barman Cloud Plugin. SC numbers
  were renumbered so SC-009 is the backup-before-migration criterion.
- The 7 day deadline now starts when the encrypted storage is proven and every volume has a
  restore-tested backup (Assumptions). The prerequisite phase is outside the 7 days.
- Corrected 2026-10-03: the Hetzner cluster already has web identity (a self-hosted issuer and
  the pod-identity webhook; `shared-postgres` already uses it to read the old backups). An earlier
  draft wrongly said it did not, from a stale clone of the Terraform repository. The owner then
  chose web identity (IRSA) for both Velero and the databases. This removed the control-plane
  change, the OIDC hosting and the Roles Anywhere sidecar work from the plan.
- Refined 2026-10-03 after the analysis pass: FR-015 and SC-009 now say what a backup means for a
  volume whose service is stopped (dated after its last change). FR-018 and SC-011 define "no
  corrupted chunks" as zero unreadable chunks when every chunk of every region file is read.
