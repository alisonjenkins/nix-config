---

description: "Task list for configuring the aquaero fan controller from Linux"
---

# Tasks: Aquaero Fan Controller Configuration on Linux

**Input**: Design documents from `/specs/008-aquaero-linux-config/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. The constitution (Principle II) requires a failing test first wherever behaviour is testable. Tasks marked **[HW]** need the real aquaero and cannot be tested in a build; they are the named untestable glue, and every **[HW]** write needs the owner's explicit go-ahead in that session (Principle III).

**Organization**: grouped by user story. Story order here follows dependencies, not only priority: US1 (learn the layout), then US3 (safeguards, built against a fake device), then US2 (the real curve), then US4, US5, US6.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US6, matching spec.md
- **[HW]**: needs the real device; read-only unless it says otherwise
- Every commit does one thing and builds on its own (Principle I); a task is one commit unless it says otherwise

## Path Conventions

Rust crate: `scripts/aquaero-ctl/`. Package: `pkgs/aquaero-ctl/`. Module: `modules/hardware-aquaero-ctl.nix`. Docs: `docs/`.

---

## Phase 1: Setup

**Purpose**: an empty crate that builds, lints and packages.

- [ ] T001 Create the crate `scripts/aquaero-ctl/` with `Cargo.toml` (lib plus bin, edition 2021, the dependencies from plan.md, the clippy restriction `[lints.clippy]` table from the programming skill), `Cargo.lock`, `src/lib.rs` and a `src/main.rs` that only parses nothing and exits 0
- [ ] T002 [P] Add `pkgs/aquaero-ctl/default.nix` using `rustPlatform.buildRustPackage` with a `lib.fileset` source and `cargoLock.lockFile`, `doCheck = true`, following `pkgs/token-tools/default.nix`, and register it where the other `pkgs/` entries are registered (`pkgs/default.nix`); `git add` the new files and run `nix build` on it
- [ ] T003 [P] Confirm `nix develop` provides cargo, clippy and rustfmt for `scripts/aquaero-ctl`; if not, add them to `flake-modules/dev-shells.nix`
- [ ] T004 [P] Check how `scripts/retrieval-eval` and `scripts/token-tools` wire `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` into `.pre-commit-config.yaml` or flake checks, and add the same for `scripts/aquaero-ctl`

---

## Phase 2: Foundational (blocks every story)

**Purpose**: the types every story uses, with no hardware and no writes.

- [ ] T005 [P] Write failing tests in `scripts/aquaero-ctl/tests/snapshot.rs`: round trip of bytes and metadata, rejection of a length other than 0xa93, rejection of a hash mismatch, filename `<UTC timestamp>-<label>` sorts by time, serial redaction. Confirm they fail for the right reason
- [ ] T006 [P] Write failing tests in `scripts/aquaero-ctl/tests/diff.rs`: identical snapshots give no diff, one changed byte gives one run, adjacent changes group into one run, positions that differ between two untouched snapshots are marked volatile
- [ ] T007 Implement `scripts/aquaero-ctl/src/error.rs`: one error enum per fallible operation, variants named after the operation and carrying device path, report id and byte offset where relevant (FR-017)
- [ ] T008 Implement `scripts/aquaero-ctl/src/snapshot.rs` (data-model `ConfigSnapshot`: raw `.bin` plus `.json` sidecar, SHA-256, UTC timestamp) until T005 passes
- [ ] T009 [P] Implement `scripts/aquaero-ctl/src/diff.rs` (data-model `ByteDiff`) until T006 passes
- [ ] T010 [P] Implement the `HidDevice` trait and the constants (vendor `0x0c70`, product `0xf001`, control report `0x0B` and size `0xa93`, secondary report `0x06` and size `7`, the 200 ms control gap) in `scripts/aquaero-ctl/src/hid.rs`; no real device yet
- [ ] T011 Write failing tests in `scripts/aquaero-ctl/tests/fake_device.rs` for the in-memory fake: reads and writes the 0xa93-byte report, honours the 200 ms rule through an injectable clock, and can inject a rejected write, a short read, a disconnect after N operations and a read-back that differs
- [ ] T012 Implement `scripts/aquaero-ctl/src/fake.rs` (the in-memory device with failure injection, exposed to integration tests) until T011 passes

**Checkpoint**: snapshot, diff, error, trait and fake all tested; no hardware touched.

---

## Phase 3: User Story 1 - Learn what each setting does (Priority: P1)

**Goal**: a read-only tool that snapshots and compares the stored configuration, and a recorded map from each in-scope setting to its bytes.

**Independent Test**: take two snapshots with nothing changed (device unchanged, only volatile positions differ); change one setting in Aquasuite; `diff` isolates the changed bytes (quickstart 1 and 2).

### Tests for User Story 1

- [ ] T013 [P] [US1] Write failing tests in `scripts/aquaero-ctl/tests/select.rs` for `hidraw` node selection over a fake sysfs tree in a tempdir: matches vendor and product, requires `--serial` when two devices are present (exit 4), reports "absent" distinctly from an error
- [ ] T014 [P] [US1] Write failing tests in `scripts/aquaero-ctl/tests/cli.rs` for the commands that need no device (`diff`, argument errors): exit codes 0 and 2 from contracts/cli.md, `--json` output shape

### Implementation for User Story 1

- [ ] T015 [US1] Implement node discovery and the real `hidraw` device (`HIDIOCGFEATURE` and `HIDIOCSFEATURE` through the `nix` crate, advisory lock under `/run`) in `scripts/aquaero-ctl/src/hid.rs` until T013 passes; the write method exists but nothing calls it yet
- [ ] T016 [US1] Implement `scripts/aquaero-ctl/src/cli.rs` and `src/main.rs` for `dump`, `diff` and the global options, with the exit-code mapping from contracts/cli.md, until T014 passes
- [ ] T017 [US1] Add `scripts/aquaero-ctl/README.md` with the read-only commands and how to get access to the `hidraw` node before the module exists

### Discovery on the device for User Story 1

- [ ] T018 [US1] [HW] Shut the Windows VM down so Linux owns the device again. With the owner's permission, build the tool and take a baseline snapshot twice (read-only). Record in `docs/aquaero-config.md`: which `hidrawN` serves report 0x0B, what the wrong node returns, the firmware version, and the length (research R2 and the open-items table)
- [ ] T019 [US1] [HW] Commit the redacted baseline pair under `scripts/aquaero-ctl/tests/fixtures/` (serial removed, documented in the README) and confirm the volatile positions from the untouched pair
- [ ] T020 [US1] [HW] Explain the earlier observation: with the owner's permission and the VM stopped, snapshot, write `pwm4` through the driver while watching `fan4_input`, snapshot again, and diff to see what the driver changed and whether fan 4 follows. Record the finding in `docs/aquaero-config.md`; restore the device with Aquasuite if needed
- [ ] T021 [US1] [HW] Discovery session with the device passed to the VM: for each in-scope setting, snapshot, change only that setting in Aquasuite, snapshot, return the device and `diff` with the baseline. Settings in order: fan 4 minimum speed; fan 4 control source; each curve point and the point count; the sensor-loss behaviour. Record each setting's offset, width and encoding in `docs/aquaero-config.md`
- [ ] T022 [US1] [HW] One USB capture of a save: on the host run `usbmon` read with `tshark` while Aquasuite saves one change, and record the exact report sequence, including any commit (research R6). Commit a serial-redacted summary, not the raw capture
- [ ] T023 [US1] Write failing tests in `scripts/aquaero-ctl/tests/profile.rs` that load a profile and look up fan 4 settings against the redacted fixtures, refuse an unknown firmware, and list the known firmware versions (FR-006)
- [ ] T024 [US1] Implement `scripts/aquaero-ctl/src/profile.rs` and the first `scripts/aquaero-ctl/profiles/<firmware>.toml` from T018 to T022, until T023 passes
- [ ] T025 [US1] Implement the `show` command in `scripts/aquaero-ctl/src/cli.rs` that decodes the in-scope settings from a snapshot using the profile (exit 3 when there is no profile)

**Checkpoint**: story 1 is complete and reusable on its own: read-only dump, compare, a verified profile and a written map.

---

## Phase 4: User Story 3 - Never leave the controller worse off (Priority: P1)

**Goal**: plan, backup, apply, verify and restore, proven against the fake device including every failure in spec SC-006.

**Independent Test**: against the fake device, apply then restore gives a byte-identical configuration; an unknown firmware refuses; each injected failure leaves no unreported partial state (quickstart 3 and 8).

### Tests for User Story 3

- [ ] T026 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/curve.rs`: valid curve accepted; out-of-range minimum, fewer than 2 points, non-increasing temperatures, a point below the minimum and an unsupported fan or sensor all rejected with the offending value named (FR-016); encode then decode round trip with `proptest`
- [ ] T027 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/plan.rs`: changes list shows old and new values and byte positions; every byte outside the profile's fields is preserved (FR-005); an already-applied state produces an empty plan and no write (SC-004)
- [ ] T028 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/apply.rs` against the fake: backup is saved before the first write; no backup, no write (FR-007); read-back verified after every write (FR-008); dry run writes nothing and saves nothing; the 200 ms gap is observed
- [ ] T029 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/failure.rs` against the fake: rejected write, short read, disconnect mid-sequence, read-back mismatch and unknown firmware each end with either the original or the intended bytes, or an error naming the backup and the restore command (SC-006); a second instance holding the lock exits 7
- [ ] T030 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/restore.rs`: restore returns the fake to byte-identical contents and verifies by reading back; refuses a snapshot for a different serial or unsupported firmware (SC-005)

### Implementation for User Story 3

- [ ] T031 [US3] Implement `scripts/aquaero-ctl/src/curve.rs` (data-model `FanCurve`, validation, encode and decode through the profile) until T026 passes
- [ ] T032 [US3] Implement `scripts/aquaero-ctl/src/plan.rs` (data-model `Plan`) until T027 passes
- [ ] T033 [US3] Implement `scripts/aquaero-ctl/src/apply.rs`: lock, firmware check, backup, write in the profile's commit sequence, read-back and compare, restore; until T028, T029 and T030 pass
- [ ] T034 [US3] Add the `plan`, `apply` (with `--check` and `--fail-on-drift`), `restore` and `list-backups` commands to `scripts/aquaero-ctl/src/cli.rs` with the exit codes from contracts/cli.md and the output guarantees (backup path, writes, read-back result printed on every apply, SC-003)

**Checkpoint**: the whole write path is proven against the fake; nothing has been written to the real device.

---

## Phase 5: User Story 2 - Set a coolant-driven fan curve from Linux (Priority: P1)

**Goal**: the real device follows a curve and keeps it across power loss.

**Independent Test**: apply the curve, power-cycle the machine with no software running, and watch the fans track the coolant temperature (quickstart 4 to 6).

- [ ] T035 [US2] [HW] Stage A, with the owner's go-ahead: `apply` a desired state equal to the current one (writes the unchanged snapshot back). Expect backup saved, write, read-back match, device unchanged (quickstart 4A)
- [ ] T036 [US2] [HW] Stage B, with the owner's go-ahead: change only fan 4's minimum speed, then `restore` the backup; `diff` against the original must be empty (quickstart 4B, SC-005)
- [ ] T037 [US2] [HW] Stage C, with the owner's go-ahead: `apply` the real curve (30% minimum to 100% at 45°C); `diff` against the backup shows only in-scope positions (SC-007)
- [ ] T038 [US2] [HW] Full power-off and power-on with no software started; with the coolant held near the lower and the upper temperature the fans, steady for 60 s, are within 5 points of target (SC-002). Record the readings in `docs/aquaero-config.md`
- [ ] T039 [US2] [HW] Disconnect the coolant sensor and confirm the fans go to full speed and never below the minimum (SC-009); reconnect and confirm the curve resumes
- [ ] T040 [US2] If T038 shows the curve is lost after a power cycle, treat it as a defect in the write sequence: compare against the T022 capture, fix `scripts/aquaero-ctl/src/apply.rs` test-first, and repeat T037 and T038

**Checkpoint**: the owner no longer needs Windows to set the radiator curve.

---

## Phase 6: User Story 4 - Apply declaratively from the NixOS config (Priority: P2)

**Goal**: declare the curve, switch, the device matches; switch again, nothing happens.

**Independent Test**: set a curve, switch, read the device; switch again with no write; set `mode = "check"` with a changed curve, switch, nothing written (quickstart 7).

- [ ] T041 [P] [US4] Write failing module-evaluation checks (pattern of `flake-modules/obs-config-tests.nix`) that an invalid value fails the build with a message naming it: minimum outside 0 to 100, fewer than 2 points, non-increasing temperatures, a point below the minimum, an unsupported fan or sensor (FR-016)
- [ ] T042 [US4] Implement `modules/hardware-aquaero-ctl.nix` per contracts/nix-module.md: the options, the assertions, the desired-state JSON in the store, the oneshot `aquaero-ctl-apply.service` restarted when that JSON changes, and `mode = "check"`; resolve every tool from the Nix store
- [ ] T043 [US4] Add the udev rules to `modules/hardware-aquaero-ctl.nix`: start the service when the aquaero appears (`TAG+="systemd"`, `SYSTEMD_WANTS`, the pattern in `modules/hardware-scarlett-mixer.nix`) and give the service access to the `hidraw` node
- [ ] T044 [US4] Export it in `flake-modules/nixos-modules.nix` as `hardware-aquaero-ctl` and add the tool to the package set
- [ ] T045 [US4] Enable it on `ali-desktop` in `flake-modules/hosts/ali-desktop/default.nix` with fan 4, Sensor 1, minimum 30%, points (30, 30) and (45, 100); build the host toplevel and run `just check`
- [ ] T046 [US4] [HW] With the owner's go-ahead, `just switch`: device matches; switch again and confirm no write; set `mode = "check"` with a changed curve and confirm the switch succeeds with drift logged and nothing written; unplug the device and confirm the switch still succeeds with a warning (quickstart 7, SC-004, FR-015)

---

## Phase 7: User Story 5 - Coexist with the kernel driver (Priority: P2)

**Goal**: monitoring through the driver keeps working and the tool and driver do not trip over each other.

**Independent Test**: sensors read before and after an apply, same set, sensible values, no reload (quickstart coexistence).

- [ ] T047 [P] [US5] Write failing tests in `scripts/aquaero-ctl/tests/lock.rs`: a second instance exits 7 while the first holds the lock; the lock is released on error; the 200 ms gap holds across the lock boundary
- [ ] T048 [US5] Implement the lock and the gap in `scripts/aquaero-ctl/src/hid.rs` until T047 passes (if T015 already covers it, mark this done and add only the missing assertions)
- [ ] T049 [US5] [HW] Throughout T035 to T039 and T046, read the driver's `hwmon` sensors before and after each step and record that the same sensors are present, values are sensible and the driver was not reloaded (SC-008)
- [ ] T050 [US5] Document the residual risk in `docs/aquaero-config.md`: the driver's own `pwmN` and `tempN_offset` writes cannot be locked from user space, so nothing may write them during an apply; the read-back is the safety net

---

## Phase 8: User Story 6 - Record what was learned (Priority: P3)

**Goal**: the layout, the method and the surprises written down where the next reader looks.

**Independent Test**: someone with a different aquaero of a recorded firmware can follow the doc and reproduce the mapping.

- [ ] T051 [US6] Finalise `docs/aquaero-config.md`: each in-scope setting with offset, encoding and the firmware it was verified on; the discovery method (snapshot diffs plus the USB capture); the recovery route (Aquasuite in a VM); the results of T018 to T022 and T038 to T039
- [ ] T052 [P] [US6] Write `docs/adr/0040-aquaero-config-in-user-space.md`: why user space and not a kernel module; why `hidraw` and no native library; the driver coexistence decision and its residual risk; the earlier fan2go attempt and what it showed (the calibration sweep ran despite `minPwm` and `maxPwm`, and PWM writes did not move fan 4); the persistence and commit finding
- [ ] T053 [P] [US6] Link both from `CLAUDE.md` in one short entry and from `docs/adr/README.md`
- [ ] T054 [US6] Offer the verified layout upstream as a separate follow-up (kernel driver, or liquidctl's open Aquaero pull request); write it as an issue or draft in the owner's name only if the owner asks

---

## Phase 9: Polish

- [ ] T055 [P] Run `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` in `scripts/aquaero-ctl` and fix findings, one commit per fix
- [ ] T056 [P] Remove any leftover fan2go wiring or files from earlier experiments (none are in this repository; confirm with a search) and the Windows VM's exposed SSH port, then archive the VM image per the owner's choice
- [ ] T057 Walk quickstart.md end to end on the real device and record each scenario's result in the pull request body, with the command output as evidence (Principle II)
- [ ] T058 Run `just check` and `nix build .#nixosConfigurations.ali-desktop.config.system.build.toplevel`; open the pull request with prek passing and no fixup commits left

---

## Dependencies and execution order

- **Phase 1 to 2**: Setup, then Foundational (blocks everything).
- **US1 (Phase 3)** depends on Foundational. T018 to T022 need the Windows VM stopped between sessions (it takes the device away from Linux).
- **US3 (Phase 4)** depends on Foundational and on T024 (the profile), because curve encoding and the plan read it. Its tests can start earlier against a fixture profile.
- **US2 (Phase 5)** depends on US3 and on the owner's go-ahead for each stage (A, B, C).
- **US4 (Phase 6)** depends on US3 (the CLI); T041 to T045 can proceed before US2 finishes, but T046 needs a proven write path (US2).
- **US5 (Phase 7)** overlaps US1, US3 and US2; T049 is evidence gathered during the other stories' hardware steps.
- **US6 (Phase 8)** closes after US1 and US2 produce their facts.
- **Polish** last.

## Parallel opportunities

- Setup: T002, T003 and T004 together.
- Foundational tests: T005 and T006 together; then T009 and T010 together.
- US1: T013 and T014 together.
- US3 tests: T026 to T030 together, all in different files.
- US4: T041 and T042 can start together once the contract is read.

## Implementation strategy

**MVP is US1 alone**: a read-only dump and compare tool plus a recorded layout. It writes nothing, so it is safe, and it is already useful to anyone with an aquaero. Stop there if hardware steps surface surprises.

Then add US3 (all against the fake, no hardware), then US2 in its three owner-approved stages, then US4 so the NixOS config owns the result. Deliver each phase as its own set of atomic commits; a phase boundary is a natural place for a pull request if the branch grows large.
