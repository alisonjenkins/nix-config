# Feature Specification: Encrypt the household's data volumes on the Hetzner cluster

**Feature Branch**: `docs/hetzner-inplace-patching`

**Created**: 2026-10-03

**Status**: Draft

**Input**: User description: "Make sure the volumes that hold the Matrix data are encrypted, because keeping all the household's data private matters. Make the encrypted storage the default for new volumes. Move the Postgres data to encrypted storage safely using replication, with as little downtime as possible. Take backups and prove they restore before moving anything."

## Context

The Hetzner cluster keeps its persistent data on cloud block volumes. Today none of the
household's service volumes are encrypted. The Matrix chat database (20 GiB volume, about
850 MB of data across four databases) and the Matrix media store (10 GiB) are plain. So are
the volumes for the photo service database, the document database, monitoring, the
notification server and the game server. One storage setting is the default for new volumes,
and it is unencrypted.

Three findings from reading the live cluster shape the order of work:

- The Matrix and cache databases have no backup configured on this cluster. The cluster record
  shows no backup section, no scheduled backup, and an empty recovery point.
- None of the other volumes (media, document database, monitoring, notification server, game
  server) has a backup either, and the photo service database has no backup configured. Each
  has exactly one copy.
- The previous cluster backed up its volumes and databases to the owner's object-storage
  bucket, with a volume backup tool and the database operator's own backups. The Hetzner
  cluster has neither.
- The database management tooling reports `Instance Status Extraction Error: HTTP
  communication issue` for the Matrix database, although the database pod is ready. A
  switchover relies on that channel.

Existing volumes cannot be converted in place. Each one is copied to a new encrypted volume.
The old volume's default behaviour is to be destroyed when its claim is removed, so that
needs guarding.

This feature protects data at rest on the provider's storage, including discarded or leaked
disks. It does not protect against someone who has access to the running cluster. See
Assumptions.

Related: `specs/003-hetzner-inplace-patching/` moves the call stack onto a separate machine.
That machine must only ever hold encrypted volumes, so this feature's Matrix database and
media work lands first, before that machine is created. Technical background and the unproven
points are in `docs/hetzner-inplace-patching-design.md` (section "Encryption of the Matrix
volumes") and `docs/adr/0021-patch-hetzner-master-in-place.md`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every volume has a backup, and a restore is proven (Priority: P1)

Before anything is moved, every volume that holds household data has a regular backup stored
away from it, and the operator has restored each one into a scratch environment and checked
the data. This is the safety net for the rest of the feature, and the way back once an old
volume is removed.

**Why this priority**: Moving or deleting data without a proven backup risks losing the
household's chat history, photos and files. Nothing else should start until this passes.

**Independent Test**: Take a backup of each volume, restore it into a scratch environment
separate from the live one, and compare its contents with the live data.

**Acceptance Scenarios**:

1. **Given** the databases (chat, cache and photo service), **When** the operator looks for
   backups, **Then** a full backup is taken at least daily, and changes since it are archived
   continuously, so a restore can reach a point no more than 5 minutes before a failure.
2. **Given** each volume that is not a database (media, document database, monitoring,
   notification server, game server), **When** the operator looks for backups, **Then** a
   backup is taken at least daily while its service runs, and the latest is less than 24 hours
   old. For a volume whose service is stopped, the latest backup is dated after the volume's
   last change.
3. **Given** a recent backup of each, **When** it is restored into a scratch environment,
   **Then** the databases' contents and every volume's files match the source, taken at the
   same moment.
4. **Given** a restore test, **When** it finishes, **Then** the scratch environment is removed
   and no copy of the data stays outside the encrypted storage.

---

### User Story 2 - The chat database moves to encrypted storage while staying online (Priority: P1)

The operator moves the Matrix and cache databases to an encrypted volume. The copy happens
while the database stays in use, and the only interruption is a short final switch. Chat sees
one brief reconnect, and no data is lost.

**Why this priority**: The chat database holds the household's messages and account data. It
is the most sensitive and most valuable data in scope.

**Independent Test**: Run the migration in a window with no call running. Compare row counts
and checksums for every database before and after, and time the interruption.

**Acceptance Scenarios**:

1. **Given** the databases are on plain storage, **When** the operator runs the migration,
   **Then** the data is copied to encrypted storage while the databases stay in use.
2. **Given** the copy is complete and has caught up, **When** the operator makes the final
   switch, **Then** chat and sign-in are interrupted for at most 2 minutes in total.
3. **Given** the switch is done, **When** the operator checks, **Then** every database's row
   counts and checksums match the pre-migration snapshot and the services work.
4. **Given** the new storage is in use, **When** the operator inspects the raw volume,
   **Then** the data is unreadable without the passphrase.

---

### User Story 3 - The old plain copy is removed as soon as the move is verified (Priority: P2)

The old plaintext volume is kept only until the migration is verified, so the operator can go
back if the check fails, and it cannot be destroyed by accident before then. As soon as the
verification passes and a fresh backup of the new volume's data exists, the old volume is
removed, so no plaintext copy of the data lingers. There is no fixed waiting period.

**Why this priority**: The household wants plaintext gone as soon as it is safe. The old volume
is the way back only until the new copy is proven. After that, the backup is the way back.

**Independent Test**: Remove the claim for the old volume before verification and confirm the
volume survives. Run the verification, take the fresh backup, remove the old volume, and
confirm it is gone from the provider.

**Acceptance Scenarios**:

1. **Given** the migration is complete but not yet verified, **When** the old volume's claim
   is removed, **Then** the volume is retained.
2. **Given** the verification has failed, **When** the operator checks, **Then** the old volume
   is still intact and still the one in use, or can be switched back to.
3. **Given** the verification has passed and a fresh backup of the new volume's data exists,
   **When** the operator removes the old volume, **Then** it no longer exists at the provider.
4. **Given** the verification has passed, **When** the operator reviews the migration, **Then**
   the old volume is removed within 24 hours.

---

### User Story 4 - Media moves to encrypted storage (Priority: P2)

The Matrix media store is copied to an encrypted volume during a quiet window, and no file
is lost or changed.

**Why this priority**: Media holds uploaded files and pictures, which are private.

**Independent Test**: Compare file counts and checksums between the old and new volumes, then
open a few known files from the chat client.

**Acceptance Scenarios**:

1. **Given** the media store, **When** it is copied, **Then** every file's path, size and
   checksum match the original.
2. **Given** the cut-over, **When** the operator opens known media in the chat client, **Then**
   it loads.

---

### User Story 5 - New volumes are encrypted by default (Priority: P2)

Any new volume created without naming a storage setting is encrypted. A test volume proves
it. Existing volumes and workloads are unaffected until they are migrated.

**Why this priority**: Without this, the next new service stores its data in plain text by
accident.

**Independent Test**: Create a small test volume with no storage setting named, mount it, and
inspect the raw volume.

**Acceptance Scenarios**:

1. **Given** the default is set, **When** a volume is created without naming a setting,
   **Then** it is encrypted.
2. **Given** the default is set, **When** the existing workloads run, **Then** none restarts
   or changes because of it.
3. **Given** a node mounts an encrypted volume, **When** the volume is created and mounted,
   **Then** the first mount completes within the same time as a plain volume plus 1 minute.

---

### User Story 6 - The passphrase cannot be lost (Priority: P2)

The passphrase protecting the volumes is stored in two independent places, and the operator
has proven that either can recover the data. Losing it would mean losing the data.

**Why this priority**: Encryption turns a lost passphrase into permanent data loss.

**Independent Test**: In a fresh scratch environment, mount an encrypted volume copy using
only the saved passphrase from each place in turn.

**Acceptance Scenarios**:

1. **Given** the passphrase is created, **When** the operator checks, **Then** it exists in
   the encrypted configuration repository and in the owner's password manager.
2. **Given** each saved copy in turn, **When** it is used to mount a copy of an encrypted
   volume in a scratch environment, **Then** the data is readable.

---

### User Story 7 - Every other household volume is encrypted as fast as is safe (Priority: P2)

The photo service database, the document database, monitoring, the notification server and
the game server's data move to encrypted volumes straight after the Matrix data, not
months later. Each is its own migration with the same checks. Small and quick volumes go
first, and several can move in the same window when they do not share a service. The goal is
that no household data stays unencrypted for longer than it takes to do the work safely.

**Why this priority**: The household wants all of its data private, and a plain volume left
behind is the weakest point. The Matrix data goes first only because it is the most
sensitive.

**Independent Test**: Per volume: copy, compare, switch, verify, remove, as in stories 2 to 4.
Then list every volume in the cluster and check none uses the old plain setting.

**Acceptance Scenarios**:

1. **Given** a remaining volume, **When** it is migrated, **Then** its data matches and the
   service works.
2. **Given** a volume whose service has a database (the photo service), **When** it is
   migrated, **Then** it has a restore-tested backup first, as in story 1.
3. **Given** every volume is migrated, **When** the operator lists the cluster's volumes,
   **Then** none uses the old plain setting.
4. **Given** the encrypted storage has been proven, **When** 7 days have passed, **Then**
   every household volume is encrypted.

---

### User Story 8 - The Minecraft world can be rolled back to before a grief (Priority: P2)

The Minecraft world is backed up while people are playing, and once more after the last player
leaves. Backups are kept for up to a year, with older ones thinning out. If someone griefs the
world and nobody notices for weeks, the owner restores the world as it was before, or restores
an old copy next to the live one to compare.

**Why this priority**: The world is the one volume whose damage can be deliberate and quiet.
Normal backups that expire after a few days cannot undo a grief found weeks later.

**Independent Test**: Run a play session, make a recognisable change, and wait for a backup.
Make a second change. Restore the first backup into a scratch location and confirm it holds the
first change and not the second. Repeat with a backup that is more than a month old.

**Acceptance Scenarios**:

1. **Given** the server is running, **When** 2 hours pass, **Then** a new world backup exists,
   and no player is disconnected while it is taken.
2. **Given** the last player has left and the server is about to stop, **When** it stops,
   **Then** a backup taken after the last change exists, and the server stops only once it
   completes or a limit passes.
3. **Given** the backups, **When** the owner lists them, **Then** there is one every 2 hours
   for the last 3 days, one a day for the last 90 days, and one a week for the last year.
4. **Given** a backup from a chosen date, **When** the owner restores it to a scratch location,
   **Then** the live world is untouched and the restored world is complete and usable.
5. **Given** a backup taken while players were building, **When** it is restored, **Then** the
   world loads with no corrupted chunks.

---

### Edge Cases

- The copy fails or lags and never catches up. The operator stays on the old volume. Nothing
  is switched, and the new volume is removed.
- The database tooling still reports its status error. The migration does not start until the
  error is cleared.
- The final switch fails. The old volume is still current, so the operator returns to it.
- The passphrase is missing from the cluster when a pod starts. The pod stays pending, and the
  running pods that already mounted their volumes are unaffected.
- A node restarts mid-migration. The copy resumes from where it was.
- A file-level backup of a busy volume is inconsistent (for example the document database or
  the metrics store). The restore test catches it, and the service is paused for the backup
  until a consistent method is found.
- The backup bucket is unreachable or write access is denied. No migration starts.
- The end-of-session backup fails or takes too long. The server still stops after a limit, so
  it is not left running at cost, and the failure is reported loudly.
- The server is stopped or restarted by something other than the idle timeout. The next
  scheduled backup still runs, but there is no end-of-session backup for that session.
- A world backup runs while the server is paused for a save. Players see no disconnect, though
  a brief hitch is possible.
- A call starts during the window. The operator checks before the final switch and defers it.
- The first mount of an encrypted volume is slow. The procedure allows for it and does not
  treat it as a failure.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Matrix databases and media store MUST be stored on encrypted volumes.
- **FR-002**: A volume created without naming a storage setting MUST be encrypted.
- **FR-003**: The passphrase MUST be stored in the encrypted configuration repository and in
  the owner's password manager, and MUST NOT be stored in plain text anywhere.
- **FR-004**: The databases (chat, cache and photo service) MUST have a full backup at least
  daily plus continuous archiving of changes, so a restore loses at most 5 minutes of data,
  and a restore MUST be tested before any migration.
- **FR-015**: Every volume that is not a database MUST have a backup at least daily while its
  service runs, stored away from the volume. A volume whose service is stopped (monitoring
  dashboards, the game server when idle) MUST have a backup dated after its last change, since
  nothing changes while it is stopped. A restore of each MUST be tested before that volume's
  migration. The backups MUST be encrypted at rest.
- **FR-016**: Backups MUST authenticate to the backup storage with short-lived credentials. No
  long-lived storage access key MUST be kept on the cluster for backups.
- **FR-017**: The Minecraft world MUST be backed up at least every 2 hours while the server is
  running, and once more after the last player leaves and before the server stops.
- **FR-018**: A world backup taken while the server is running MUST be consistent: it MUST
  restore with no corrupted chunks, and taking it MUST NOT disconnect any player. "No corrupted
  chunks" means every chunk of the restored world can be read in full, checked by reading each
  chunk of every region file, with zero unreadable chunks.
- **FR-019**: World backups MUST be kept in tiers: every 2 hours for 3 days, daily for 90 days,
  and weekly for a year.
- **FR-020**: The owner MUST be able to restore any kept world backup to a scratch location
  without touching the live world.
- **FR-005**: The database migration MUST copy data while the databases stay in use, with an
  interruption of no more than 2 minutes at the final switch.
- **FR-006**: A migration MUST be verified before the old volume is touched. Verification has
  three parts, and all must pass: a data comparison against a snapshot taken at the moment of
  the switch (row counts and checksums for databases, file counts and checksums for media),
  the service passing its health checks on the new volume, and a functional check that the
  service really works (for chat: send and read a message and open known media).
- **FR-007**: The old volume MUST be retained, and protected from automatic destruction, until
  the migration passes verification (FR-006) and a fresh backup of the new volume's data
  exists. There is no fixed waiting period.
- **FR-008**: The old plain volume MUST be removed within 24 hours of a verified migration.
- **FR-009**: Migration steps that interrupt chat MUST run in a window with no call active.
- **FR-010**: The operator MUST be able to return to the old volume at any point before it is
  removed.
- **FR-011**: The procedure MUST record each step, its result and its time in UTC.
- **FR-012**: Every other household volume MUST be encrypted within 7 days of the encrypted
  storage being proven, using the same verification and removal rules. Volumes whose services are
  independent MAY move in the same window.
- **FR-013**: Locations that stay unencrypted (for example temporary files on a machine's own
  disk) MUST be listed and accepted by the owner, or moved to a protected location.
- **FR-014**: The database management tooling's status error MUST be cleared before the
  database migration starts.

### Key Entities

- **Data volume**: A block volume holding a service's persistent data.
- **Passphrase**: The secret that unlocks the encrypted volumes. Losing it means losing the
  data.
- **Backup**: A restorable copy of the databases, stored separately.
- **Storage setting (default)**: What a volume gets when none is named.
- **Migration run**: One move of one volume, with its copy, switch, verification and removal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the Matrix database and media data is on encrypted volumes. Inspecting
  the raw volume shows no readable data without the passphrase.
- **SC-002**: A migration loses no data: every row count, checksum and file checksum matches
  the pre-migration snapshot.
- **SC-003**: Chat and sign-in are interrupted for at most 2 minutes in total during the
  database switch.
- **SC-004**: A restore into a scratch environment recovers 100% of the databases, to a point
  within 5 minutes of the chosen moment, and 100% of the files of every other volume, and
  passes a data comparison.
- **SC-005**: 100% of volumes created without naming a storage setting are encrypted.
- **SC-006**: A recovery drill using each saved copy of the passphrase mounts an encrypted
  volume copy successfully.
- **SC-007**: No plaintext copy of any household volume remains 24 hours after that volume's
  migration passes verification.
- **SC-008**: Every household volume is encrypted within 7 days of the encrypted storage
  being proven, and none uses the old plain setting.
- **SC-009**: Before any volume is migrated, 100% of household volumes have a current backup
  (less than 24 hours old, or dated after the volume's last change if its service is stopped;
  databases: archived to within 5 minutes), and each has had a restore test.
- **SC-010**: For 100% of play sessions, a world backup exists that was taken after the last
  player left, unless the server was stopped by something other than the idle timeout.
- **SC-011**: A world backup restored from any point in the last 90 days, at 2 hour spacing for
  the last 3 days, has zero unreadable chunks, and the restore leaves the live world unchanged.
- **SC-012**: The cluster holds no long-lived storage access key for backups.

## Assumptions

- Encryption protects data at rest on the provider's storage, including discarded disks. It
  does not protect against anyone with access to the cluster, because the passphrase is a
  cluster secret.
- One passphrase covers all encrypted volumes. Separate passphrases per volume are not worth
  the extra loss risk here.
- Each machine's own disk stays unencrypted. Temporary files from the database and the chat
  server land there. FR-013 covers listing and accepting this.
- Backups go to the existing object-storage bucket in the owner's AWS account, which already
  holds the previous Matrix database backups. It is a different provider from Hetzner, so one
  provider's outage or account problem does not take the data and its backups together.
  Backup contents are encrypted in transit and at rest by that storage.
- Steps that interrupt chat run on weekday daytime, when the household is not in a call. The
  procedure still checks for an active call each time (FR-009).
- Order of work (owner's decision, 2026-10-03): this feature lands first. The Matrix data is
  backed up and moved to encrypted volumes on the current machine, and only then does
  `specs/003-hetzner-inplace-patching/` create the call machine.
- The encrypted storage method works with the installed storage driver version and with
  resizing. This is unproven and is tested with a throwaway volume first.
- A changed storage setting on an existing database cluster is used for new copies only. This
  is unproven and is tested on a scratch database cluster first.
- The final switch needs the database management tooling to be healthy, which is why FR-014
  comes first.
- Removing the old volume as soon as verification passes (owner's decision, 2026-10-03) means
  the way back afterwards is the backup, not the old volume. That is why every volume gets a
  restore-tested backup first, and why FR-006 requires a functional check as well as a data
  comparison.
- Backups come first (owner's decision, 2026-10-03). The owner chose Velero for the
  non-database volumes, with the database operator's own backups (through its supported backup
  plugin) for the databases. The plan decides the details.
- Backup credentials (owner's decision, 2026-10-03): Velero and the databases both use web
  identity (IRSA). The cluster signs a short-lived token, and AWS exchanges it for temporary
  credentials. The Hetzner cluster already has this set up and uses it today to read the old
  Matrix backups. Neither keeps a long-lived key. If the mechanism proves unusable in
  rehearsal, work stops and the owner decides; no static key is used without that decision.
- Write access to the backup bucket from the Hetzner cluster does not exist yet. The cluster
  only reads from it today, to restore the Matrix database from the old cluster's backups.
  Granting it is a dependency on the cloud-account infrastructure repository.
- "Proven" in FR-012 and SC-008 means both: the encrypted storage test has passed, and every
  volume has a restore-tested backup. The 7 day period starts then, not when work begins.
  Getting the backups and credentials working is the prerequisite phase and is not inside the
  7 days. It is mostly new roles and manifests on top of the web identity the cluster already
  has.
- The Hetzner volume driver offers no volume snapshots, so volume backups copy files from a
  running volume. Services that write continuously may need to be paused or quiesced for a
  consistent copy. The restore test shows whether each backup is usable.
- Monitoring history is copied to the encrypted volume, not discarded (owner's decision,
  2026-10-03). The metrics volume grows, so its copy is the slowest of the small volumes and
  is started early.
- Speed is limited by the no-call windows for the Matrix data and by the sequence of the
  database moves, not by the number of volumes. Volumes that share no service can move in
  parallel.
- Matrix messages in encrypted rooms are already end-to-end encrypted. The database still
  holds account data, metadata, unencrypted rooms and notification data.
- Constitution III applies: every change is made in code and applied through the normal path,
  and live changes need the owner's explicit permission.
