---

description: "Task list for configuring the aquaero fan controller from Linux"
---

# Tasks: Aquaero Fan Controller Configuration on Linux

**Input**: Design documents from `/specs/008-aquaero-linux-config/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. The constitution (Principle II) requires a failing test first wherever behaviour is testable. Tasks marked **[HW]** need the real aquaero and cannot be tested in a build; they are the named untestable glue, and every **[HW]** step that changes the device needs the owner's explicit go-ahead in that session (Principle III).

**Organization**: grouped by user story. Story order here follows dependencies, not only priority: US1 (learn the layout), then US3 (safeguards, built against a fake device), then US2 (the real curve), then US4, US5, US6.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US6, matching spec.md
- **[HW]**: needs the real device; read-only unless it says otherwise
- Every commit does one thing and builds on its own (Principle I); a task is one commit unless it says otherwise

## Path Conventions

Rust crate: `scripts/aquaero-ctl/`. Package: `pkgs/aquaero-ctl/`. Module: `modules/hardware-aquaero-ctl.nix`. Docs: `docs/`. Vendor files and anything decompiled from them stay outside the repository (`~/vms/aquasuite/`) and are never committed; only findings are recorded.

---

## Phase 1: Setup

**Purpose**: an empty crate that builds, lints and packages.

- [x] T001 Create the crate `scripts/aquaero-ctl/` with `Cargo.toml` (lib plus bin, edition 2021, the dependencies from plan.md, the clippy restriction `[lints.clippy]` table from the programming skill), `Cargo.lock`, `src/lib.rs` and a `src/main.rs` that only parses nothing and exits 0
- [x] T002 [P] Add `pkgs/aquaero-ctl/default.nix` using `rustPlatform.buildRustPackage` with a `lib.fileset` source and `cargoLock.lockFile`, `doCheck = true`, following `pkgs/token-tools/default.nix`, and register it where the other `pkgs/` entries are registered (`pkgs/default.nix`); `git add` the new files and run `nix build` on it
- [x] T003 [P] Confirm `nix develop` provides cargo, clippy and rustfmt for `scripts/aquaero-ctl`; if not, add them to `flake-modules/dev-shells.nix`. The root dev shell has no Rust toolchain, so this follows `scripts/retrieval-eval`: a small `scripts/aquaero-ctl/flake.nix` dev shell
- [x] T004 [P] Check how `scripts/retrieval-eval` and `scripts/token-tools` wire `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` into `.pre-commit-config.yaml` or flake checks, and add the same for `scripts/aquaero-ctl`. Neither crate has such a hook or check (only the `[lints.clippy]` table), so the package's check phase runs both, and a badly formatted source fails `nix build .#aquaero-ctl`

---

## Phase 2: Foundational (blocks every story)

**Purpose**: the types every story uses, with no hardware and no writes. The lock and the control gap live here, with their tests first, because the real device (T017) and the apply path (T043) both rest on them.

- [x] T005 [P] Write failing tests in `scripts/aquaero-ctl/tests/snapshot.rs`: round trip of bytes and metadata, rejection of a length other than 0xa93, rejection of a hash mismatch, filename `<UTC timestamp>-<label>` sorts by time, serial redaction. Confirm they fail for the right reason
- [x] T006 [P] Write failing tests in `scripts/aquaero-ctl/tests/diff.rs`: identical snapshots give no diff, one changed byte gives one run, adjacent changes group into one run, positions that differ between two untouched snapshots are marked volatile
- [x] T007 Implement `scripts/aquaero-ctl/src/error.rs`: one error enum per fallible operation, variants named after the operation and carrying device path, report id and byte offset where relevant (FR-017)
- [x] T008 Implement `scripts/aquaero-ctl/src/snapshot.rs` (data-model `ConfigSnapshot`: raw `.bin` plus `.json` sidecar, SHA-256, UTC timestamp) until T005 passes
- [x] T009 [P] Implement `scripts/aquaero-ctl/src/diff.rs` (data-model `ByteDiff`) until T006 passes
- [x] T010 [P] Implement the `HidDevice` trait and the constants (vendor `0x0c70`, product `0xf001`, control report `0x0B` and size `0xa93`, secondary report `0x06` and size `7`, the 200 ms control gap) in `scripts/aquaero-ctl/src/hid.rs`; no real device yet
- [x] T011 Write failing tests in `scripts/aquaero-ctl/tests/fake_device.rs` for the in-memory fake: reads and writes the 0xa93-byte report, honours the 200 ms rule through an injectable clock, and can inject a rejected write, a short read, a disconnect after N operations and a read-back that differs
- [x] T012 Implement `scripts/aquaero-ctl/src/fake.rs` (the in-memory device with failure injection, exposed to integration tests) until T011 passes. It is always compiled rather than behind a Cargo feature: it is small, and a feature would add a build-matrix entry for no gain
- [x] T013 [P] Write failing tests in `scripts/aquaero-ctl/tests/lock.rs`: a second instance exits 7 while the first holds the lock; the lock is released on error and on drop; at least 200 ms separates two control operations even across the lock boundary
- [x] T014 Implement `scripts/aquaero-ctl/src/lock.rs` (advisory lock under `/run` and the control-gap enforcement) until T013 passes

**Checkpoint**: snapshot, diff, error, trait, fake and lock all tested; no hardware touched.

---

## Phase 3: User Story 1 - Learn what each setting does (Priority: P1)

**Goal**: a read-only tool that snapshots and compares the stored configuration, and a recorded map from each in-scope setting to its bytes. The tool never writes in this phase; some discovery steps do change the device's settings, through the vendor software or the kernel driver, and those are marked and need the owner's go-ahead.

**Independent Test**: take two snapshots with nothing changed (device unchanged, only volatile positions differ); change one setting in Aquasuite; `diff` isolates the changed bytes (quickstart 1 and 2).

### Tests for User Story 1

- [ ] T015 [P] [US1] Write failing tests in `scripts/aquaero-ctl/tests/select.rs` for `hidraw` node selection over a fake sysfs tree in a tempdir: matches vendor and product, requires `--serial` when two devices are present (exit 4), reports "absent" distinctly from an error
- [ ] T016 [P] [US1] Write failing tests in `scripts/aquaero-ctl/tests/cli.rs` for the commands that need no device (`diff`, argument errors): exit codes 0 and 2 from contracts/cli.md, `--json` output shape

### Implementation for User Story 1

- [ ] T017 [US1] Implement node discovery and the real `hidraw` device (`HIDIOCGFEATURE` and `HIDIOCSFEATURE` through the `nix` crate, using the lock and gap from T014) in `scripts/aquaero-ctl/src/hid.rs` until T015 passes; the write method exists but nothing calls it yet
- [ ] T018 [US1] Implement `scripts/aquaero-ctl/src/cli.rs` and `src/main.rs` for `dump`, `diff` and the global options, with the exit-code mapping from contracts/cli.md, until T016 passes
- [ ] T019 [US1] Add `scripts/aquaero-ctl/README.md` with the read-only commands and how to get access to the `hidraw` node before the module exists

### Discovery environment for User Story 1

- [ ] T020 [US1] Start `docs/aquaero-config.md` and record the discovery environment as it stands: the Windows VM (quickemu config `~/vms/aquasuite/windows-10.conf`, aquaero passed through), Aquasuite X.79 and the .NET 8 Desktop Runtime installed in it, why X.79 (X.94 needs an update-service extension), the installed files extracted at `~/vms/aquasuite/aquasuite-files/`, how the guest is driven over VNC (the typing workarounds), and that a running VM takes the device away from Linux
- [ ] T021 [US1] [HW] Make the USB capture tooling ready on the host: load `usbmon`, run `tshark` against the aquaero's bus without root (or record the exact `sudo` the owner must run), and confirm it sees traffic while Aquasuite is open in the VM. Record the commands and permissions in `docs/aquaero-config.md`; no device setting changes

### Static analysis of the vendor software for User Story 1 (no device needed; findings are leads to verify)

- [ ] T022 [US1] Decompile `AquaComputerServiceLib.dll` and `AquaComputerCmd.exe` with `ilspycmd` into `~/vms/aquasuite/decompiled/` (done once on 2026-10-13; record the exact command and tool version in `docs/aquaero-config.md` so it can be repeated). Note that `rea`'s managed provider reached its 64 MiB metadata budget on the library and returned partial coverage, and that the binaries carry anti-tamper protection, so decompiled output is read, never run or debugged, and no protection is defeated. Nothing decompiled is committed
- [ ] T023 [US1] Read the settings model in the decompiled library (`FanSetup`, `ControllerSetup`, `ControllerCurve`, `SensorCurve`, `CurveMode`, `FanControlMode`, `IAquaero5Settings`) and record in `docs/aquaero-config.md`, with class and line references: the curve structure (point count, value ranges, modes) and what each fan-control mode means. Mark every finding a lead to verify in T029
- [ ] T024 [US1] Find where the settings are converted to and from the 0xa93-byte report and what calls `GetFeatureReport` and `SetFeatureReport`, including any save or commit sequence; record offsets and the sequence as leads in `docs/aquaero-config.md`. If that code is encrypted or unreadable, say so and rely on T029 and T030 instead

### Discovery on the device for User Story 1

- [ ] T025 [US1] [HW] Shut the Windows VM down so Linux owns the device again. With the owner's permission, build the tool and take a baseline snapshot twice (read-only). Record in `docs/aquaero-config.md`: which `hidrawN` serves report 0x0B, what the wrong node returns, the firmware version, and the length (research R2 and the open-items table)
- [ ] T026 [US1] [HW] Commit the redacted baseline pair under `scripts/aquaero-ctl/tests/fixtures/` (serial removed, documented in the README) and confirm the volatile positions from the untouched pair
- [ ] T027 [US1] [HW] With the owner's go-ahead, preserve the device's original configuration before any experiment: export it from Aquasuite in the VM (its settings file) and keep it next to the baseline snapshot, so every later change can be undone from the vendor software
- [ ] T028 [US1] [HW] Explain the earlier observation: with the owner's permission and the VM stopped, snapshot, write `pwm4` through the driver while watching `fan4_input`, snapshot again, and diff to see what the driver changed and whether fan 4 follows. Record the finding in `docs/aquaero-config.md`; restore the device from the T027 export if needed
- [ ] T029 [US1] [HW] Discovery session with the owner's go-ahead and the device passed to the VM: for each in-scope setting, snapshot, change only that setting in Aquasuite, snapshot, return the device and `diff` with the baseline. Settings in order: fan 4 minimum speed; fan 4 control source; each curve point and the point count; the sensor-loss behaviour. Use the leads from T023 and T024 to predict the offsets first, then confirm or correct each by the diff. Record each setting's offset, width and encoding in `docs/aquaero-config.md`
- [ ] T030 [US1] [HW] One USB capture of a save: on the host run `usbmon` read with `tshark` (T021) while Aquasuite saves one change, and record the exact report sequence, including any commit (research R6). Compare with T024's lead. Commit a serial-redacted summary, not the raw capture
- [ ] T031 [US1] [HW] With the owner's go-ahead, return the device to its original configuration: re-import the T027 export in Aquasuite, take a snapshot, and confirm the diff against the baseline is empty apart from volatile positions
- [ ] T032 [US1] Write failing tests in `scripts/aquaero-ctl/tests/profile.rs` that load a profile and look up fan 4 settings against the redacted fixtures, refuse an unknown firmware, and list the known firmware versions (FR-006)
- [ ] T033 [US1] Implement `scripts/aquaero-ctl/src/profile.rs` and the first `scripts/aquaero-ctl/profiles/<firmware>.toml` from T022 to T030, until T032 passes
- [ ] T034 [US1] Implement the `show` command in `scripts/aquaero-ctl/src/cli.rs` that decodes the in-scope settings from a snapshot using the profile (exit 3 when there is no profile)
- [ ] T035 [US1] Draft `docs/adr/0040-aquaero-config-in-user-space.md` with what is known so far (user space and not a kernel module, `hidraw` and no native library, the discovery method and what the static analysis and the diffs showed, the earlier fan2go attempt), and link it from `docs/aquaero-config.md`. It lands in the same pull request as the code that rests on these findings (Principle VI); T060 finalises it

**Checkpoint**: story 1 is complete and reusable on its own: read-only dump, compare, a verified profile and a written map, with the device back in its original configuration.

---

## Phase 4: User Story 3 - Never leave the controller worse off (Priority: P1)

**Goal**: plan, backup, apply, verify and restore, proven against the fake device including every failure in spec SC-006.

**Independent Test**: against the fake device, apply then restore gives a byte-identical configuration; an unknown firmware refuses; each injected failure leaves no unreported partial state (quickstart 3 and 8).

### Tests for User Story 3

- [ ] T036 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/curve.rs`: valid curve accepted; out-of-range minimum, fewer than 2 points, non-increasing temperatures, a point below the minimum and an unsupported fan or sensor all rejected with the offending value named (FR-016); encode then decode round trip with `proptest`
- [ ] T037 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/plan.rs`: changes list shows old and new values and byte positions; every byte outside the profile's fields is preserved (FR-005); an already-applied state produces an empty plan and no write (SC-004)
- [ ] T038 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/apply.rs` against the fake: backup is saved before the first write; no backup, no write (FR-007); read-back verified after every write (FR-008); dry run writes nothing and saves nothing; the 200 ms gap is observed
- [ ] T039 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/failure.rs` against the fake: rejected write, short read, disconnect mid-sequence, read-back mismatch and unknown firmware each end with either the original or the intended bytes, or an error naming the backup and the restore command (SC-006); a second instance holding the lock exits 7
- [ ] T040 [P] [US3] Write failing tests in `scripts/aquaero-ctl/tests/restore.rs`: restore returns the fake to byte-identical contents and verifies by reading back; refuses a snapshot for a different serial or unsupported firmware (SC-005)

### Implementation for User Story 3

- [ ] T041 [US3] Implement `scripts/aquaero-ctl/src/curve.rs` (data-model `FanCurve`, validation, encode and decode through the profile) until T036 passes
- [ ] T042 [US3] Implement `scripts/aquaero-ctl/src/plan.rs` (data-model `Plan`) until T037 passes
- [ ] T043 [US3] Implement `scripts/aquaero-ctl/src/apply.rs`: lock (T014), firmware check, backup, write in the profile's commit sequence, read-back and compare, restore; until T038, T039 and T040 pass
- [ ] T044 [US3] Add the `plan`, `apply` (with `--check` and `--fail-on-drift`), `restore` and `list-backups` commands to `scripts/aquaero-ctl/src/cli.rs` with the exit codes from contracts/cli.md and the output guarantees (backup path, writes, read-back result printed on every apply, SC-003)

**Checkpoint**: the whole write path is proven against the fake; nothing has been written to the real device.

---

## Phase 5: User Story 2 - Set a coolant-driven fan curve from Linux (Priority: P1)

**Goal**: the real device follows a curve and keeps it across power loss.

**Independent Test**: apply the curve, power-cycle the machine with no software running, and watch the fans track the coolant temperature (quickstart 4 to 6).

- [ ] T045 [US2] [HW] Stage A, with the owner's go-ahead: `apply` a desired state equal to the current one (writes the unchanged snapshot back). Expect backup saved, write, read-back match, device unchanged (quickstart 4A)
- [ ] T046 [US2] [HW] Stage B, with the owner's go-ahead: change only fan 4's minimum speed, then `restore` the backup; `diff` against the original must be empty (quickstart 4B, SC-005)
- [ ] T047 [US2] [HW] Stage C, with the owner's go-ahead: `apply` the real curve (30% minimum to 100% at 45°C); `diff` against the backup shows only in-scope positions (SC-007)
- [ ] T048 [US2] [HW] Full power-off and power-on with no software started; with the coolant held near the lower and the upper temperature the fans, steady for 60 s, are within 5 points of target (SC-002). Record the readings in `docs/aquaero-config.md`
- [ ] T049 [US2] [HW] Disconnect the coolant sensor and confirm the fans go to full speed and never below the minimum (SC-009); reconnect and confirm the curve resumes
- [ ] T050 [US2] If T048 shows the curve is lost after a power cycle, treat it as a defect in the write sequence: compare against the T030 capture, fix `scripts/aquaero-ctl/src/apply.rs` test-first, and repeat T047 and T048

**Checkpoint**: the owner no longer needs Windows to set the radiator curve.

---

## Phase 6: User Story 4 - Apply declaratively from the NixOS config (Priority: P2)

**Goal**: declare the curve, switch, the device matches; switch again, nothing happens.

**Independent Test**: set a curve, switch, read the device; switch again with no write; set `mode = "check"` with a changed curve, switch, nothing written (quickstart 7).

- [ ] T051 [P] [US4] Write failing module-evaluation checks (pattern of `flake-modules/obs-config-tests.nix`) that an invalid value fails the build with a message naming it: minimum outside 0 to 100, fewer than 2 points, non-increasing temperatures, a point below the minimum, an unsupported fan or sensor (FR-016)
- [ ] T052 [US4] Implement `modules/hardware-aquaero-ctl.nix` per contracts/nix-module.md: the options, the assertions, the desired-state JSON in the store, the oneshot `aquaero-ctl-apply.service` restarted when that JSON changes, and `mode = "check"`; resolve every tool from the Nix store
- [ ] T053 [US4] Add the udev rules to `modules/hardware-aquaero-ctl.nix`: start the service when the aquaero appears (`TAG+="systemd"`, `SYSTEMD_WANTS`, the pattern in `modules/hardware-scarlett-mixer.nix`) and give the service access to the `hidraw` node
- [ ] T054 [US4] Export it in `flake-modules/nixos-modules.nix` as `hardware-aquaero-ctl` and add the tool to the package set
- [ ] T055 [US4] Enable it on `ali-desktop` in `flake-modules/hosts/ali-desktop/default.nix` with fan 4, Sensor 1, minimum 30%, points (30, 30) and (45, 100); build the host toplevel and run `just check`
- [ ] T056 [US4] [HW] With the owner's go-ahead, `just switch`: device matches; switch again and confirm no write; set `mode = "check"` with a changed curve and confirm the switch succeeds with drift logged and nothing written; unplug the device and confirm the switch still succeeds with a warning (quickstart 7, SC-004, FR-015)

---

## Phase 7: User Story 5 - Coexist with the kernel driver (Priority: P2)

**Goal**: monitoring through the driver keeps working and the tool and driver do not trip over each other. The lock and the control gap are already in place from Phase 2; this phase is the evidence and the written limits.

**Independent Test**: sensors read before and after an apply, same set, sensible values, no reload (quickstart coexistence).

- [ ] T057 [US5] [HW] Throughout T045 to T049 and T056, read the driver's `hwmon` sensors before and after each step and record that the same sensors are present, values are sensible and the driver was not reloaded (SC-008)
- [ ] T058 [US5] Document the residual risk in `docs/aquaero-config.md`: the driver's own `pwmN` and `tempN_offset` writes cannot be locked from user space, so nothing may write them during an apply; the read-back is the safety net

---

## Phase 8: User Story 6 - Record what was learned (Priority: P3)

**Goal**: the layout, the method and the surprises written down where the next reader looks.

**Independent Test**: someone with a different aquaero of a recorded firmware can follow the doc and reproduce the mapping.

**Pull requests**: the docs and the ADR travel with the code that rests on them. If the work ships as one pull request, all of this lands with it. If it is split by phase, the Phase 3 pull request carries `docs/aquaero-config.md` and the ADR draft from T035, and each later pull request updates both for the findings it contains (Principle VI).

- [ ] T059 [US6] Finalise `docs/aquaero-config.md`: each in-scope setting with offset, encoding and the firmware it was verified on; the discovery method (static analysis, snapshot diffs and the USB capture); the recovery route (Aquasuite in a VM and the T027 export); the results of T025 to T031 and T048 to T049
- [ ] T060 [P] [US6] Finalise `docs/adr/0040-aquaero-config-in-user-space.md` (drafted in T035): add the driver coexistence decision and its residual risk, the persistence and commit finding, and the fan2go attempt (the calibration sweep ran despite `minPwm` and `maxPwm`, and PWM writes did not move fan 4, with what T028 showed)
- [ ] T061 [P] [US6] Link both from `CLAUDE.md` in one short entry and from `docs/adr/README.md`
- [ ] T062 [US6] Offer the verified layout upstream as a separate follow-up (kernel driver, or liquidctl's open Aquaero pull request); write it as an issue or draft in the owner's name only if the owner asks

---

## Phase 9: Polish

- [ ] T063 [P] Run `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` in `scripts/aquaero-ctl` and fix findings, one commit per fix
- [ ] T064 [P] Remove any leftover fan2go wiring or files from earlier experiments (none are in this repository; confirm with a search) and the Windows VM's exposed SSH port, then archive the VM image per the owner's choice
- [ ] T065 Walk quickstart.md end to end on the real device and record each scenario's result in the pull request body, with the command output as evidence (Principle II)
- [ ] T066 Run `just check` and `nix build .#nixosConfigurations.ali-desktop.config.system.build.toplevel`; open the pull request with prek passing and no fixup commits left

---

## Dependencies and execution order

- **Phase 1 to 2**: Setup, then Foundational (blocks everything).
- **US1 (Phase 3)** depends on Foundational. T022 to T024 (static analysis) need no device and can run any time after T020. T021 and T025 to T031 need the device; the Windows VM takes it away from Linux, so T025 (VM stopped) and T029 to T031 (VM running) alternate.
- **US3 (Phase 4)** depends on Foundational and on T033 (the profile), because curve encoding and the plan read it. Its tests can start earlier against a fixture profile.
- **US2 (Phase 5)** depends on US3 and on the owner's go-ahead for each stage (A, B, C).
- **US4 (Phase 6)** depends on US3 (the CLI); T051 to T055 can proceed before US2 finishes, but T056 needs a proven write path (US2).
- **US5 (Phase 7)** is evidence gathered during the other stories' hardware steps; its lock and gap are in Foundational.
- **US6 (Phase 8)** closes after US1 and US2 produce their facts; the ADR draft (T035) comes with US1.
- **Polish** last.

## Parallel opportunities

- Setup: T002, T003 and T004 together.
- Foundational tests: T005, T006 and T013 together; then T009 and T010 together.
- US1: T015 and T016 together; T022 to T024 alongside the code tasks.
- US3 tests: T036 to T040 together, all in different files.
- US4: T051 and T052 can start together once the contract is read.

## Implementation strategy

**MVP is US1 alone**: a read-only dump and compare tool plus a recorded layout and the device returned to its original configuration. The tool writes nothing, so it is safe, and it is already useful to anyone with an aquaero. Stop there if hardware steps surface surprises.

Then add US3 (all against the fake, no hardware), then US2 in its three owner-approved stages, then US4 so the NixOS config owns the result. Deliver each phase as its own set of atomic commits. A phase boundary is a natural place for a pull request if the branch grows large, provided the docs and ADR go with it (see Phase 8).
