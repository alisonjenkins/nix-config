# Research: Aquaero Fan Controller Configuration on Linux

**Spec**: [spec.md](spec.md) | **Date**: 2026-10-13

Each item is a decision with its reason and what was rejected. Items marked **to confirm on hardware** cannot be settled from the desk: the aquaero is currently passed through to a Windows VM, so Linux cannot read it, and they become the first read-only tasks once the VM releases the device.

## Sources and how far they can be trusted

- **In-tree kernel driver** (`drivers/hwmon/aquacomputer_d5next.c`, read 2026-10-13): the only primary source read for this plan. It is authoritative for what the driver does, not for what the device accepts.
- **aerotools-ng** (Aquaero 5, Linux), **pyquaero** (Aquaero 5/6, firmware 1036 only, warns it can brick the device), **aquacomputer_d5next-hwmon issue #16**, **AquaControl**: known from search results only. Their source was **not** read for this plan. They are leads for the discovery work, not facts.
- **Owner observation, 2026-10-13**: on this device, `pwm4` through the driver read back the written values while fan 4 stayed at 1605 RPM. This is unexplained. It may mean the device ignores the driver's preset mechanism in its current stored mode, or that the write sequence did not take effect. The discovery work must explain it before any writing tool is trusted.

## R1. How the tool talks to the device

- **Decision**: open the device's `hidraw` node and use the `HIDIOCGFEATURE` and `HIDIOCSFEATURE` ioctls directly, through a small `HidDevice` trait with one real implementation and one in-memory fake.
- **Rationale**: the protocol is two feature reports (0x0B, 0xa93 bytes, and a 7-byte report 0x06) plus input reports. No C library is needed for that, so the package has no native dependency. The trait is what makes the apply logic testable with failure injection (spec SC-006).
- **Alternatives rejected**: the `hidapi` crate (pulls in a C library and a second backend for no gain); raw `libusb` (would have to detach the kernel driver, which FR-012 forbids); `/sys` or debugfs (read-only and incomplete).

## R2. Choosing the right `hidraw` node (to confirm on hardware)

- **Facts**: the driver binds only the HID interface whose `hdev->collection[1].type` is 0 and returns `-ENODEV` for the others, so the device exposes more than one interface. The driver also notes the device "does not return meaningful data" for some feature reads, yet it reads report 0x0B for PWM reads.
- **Decision**: select by vendor `0x0c70` / product `0xf001` and the owner-supplied serial, then confirm the node by issuing `GET_FEATURE 0x0B` and checking the length is 0xa93 and the header parses. Never write to a node that has not passed that check.
- **To confirm**: which `hidrawN` carries report 0x0B, and what a failed read looks like on the wrong one.

## R3. Coexisting with the kernel driver

- **Facts from the driver**: a write to `pwmN` or `tempN_offset` does a full read-modify-write of report 0x0B (get, edit, set, then the 0x06 report) and enforces a 200 ms gap between control operations (`CTRL_REPORT_DELAY`). Reading `pwmN` also issues a `GET_REPORT` for 0x0B.
- **Decision**: the tool takes an advisory lock (`flock` on a lock file under `/run`) so two copies cannot overlap; waits at least 200 ms between control operations; and never writes through the driver. The driver stays loaded. Nothing that writes `pwmN` or `tempN_offset` may run during an apply; the previous fan2go experiment is removed, so nothing does today.
- **Residual risk, stated plainly**: the driver's own writes cannot be locked from userland. If something writes `pwmN` mid-apply, the verify step (read-back) catches a mismatch but the interleave itself is not prevented. Accepted for v1, recorded in the ADR.
- **Alternative rejected**: unloading or blacklisting the driver during the apply (breaks monitoring, FR-012).

## R4. Snapshot and backup format

- **Decision**: a snapshot is two files: `<UTC timestamp>-<label>.bin` (the raw 0xa93 bytes) and `<same name>.json` (device serial, firmware version, UTC timestamp, label, length, SHA-256, tool version). Backups are snapshots written automatically before a write, under `/var/lib/aquaero-ctl/backups/<serial>/`. Discovery snapshots go where `--out` says.
- **Rationale**: raw bytes make byte-identical restore (SC-005) trivially checkable; a sidecar keeps the bytes unmodified and the metadata human-readable. Names sort by time.
- **Privacy**: the serial number is inside the dump. Fixtures committed to the repository MUST have the serial redacted by a documented step.
- **Alternative rejected**: one JSON file with hex bytes (diffs badly, invites accidental edits).

## R5. Firmware profiles

- **Decision**: a profile is a data file (TOML) keyed by firmware version, embedded in the binary at build time, listing for each in-scope setting its position, width, encoding and valid range, plus the offsets of the fields that identify the firmware. The tool refuses to write when no profile matches (FR-006) and lists the known versions.
- **Starting values (from the kernel driver, unverified)**: fan control structs start at 0x20c, 0x220, 0x234, 0x248 (fan 1 to 4, 20 bytes each); within a struct, minimum power is at +0x04, maximum at +0x06, control source at +0x10; preset values start at 0x55c, 2 bytes each; firmware version at 0x0B; serial at 0x07. Curve controllers, sensor-loss behaviour and the commit mechanism are **unknown**.
- **Alternative rejected**: constants in Rust (the layout is data discovered by experiment, and a second firmware should be a new file, not a code change).

## R6. Persistence and the commit step (to confirm on hardware)

- **Fact**: the owner reports, and the community relies on, the device remembering its configuration across power loss. The driver writes 0x0B and then a 7-byte 0x06 report after every change; what 0x06 does is not documented in the driver.
- **Gap**: snapshot diffs show what the stored configuration contains, but not **how Aquasuite makes the device save it**. The write sequence is a protocol fact, not a data fact.
- **Decision**: discovery has two parts. (a) Snapshot diffs map settings to bytes. (b) A one-off USB capture on the host (`usbmon`, read with `tshark`) while Aquasuite performs one save records the exact sequence of reports, including any commit. The tool replicates (b) only after (a) and (b) agree.
- **Alternative rejected**: assuming 0x06 is the commit. If it is, the capture shows it; if the driver's PWM mechanism never persists (a possible reason for the unexplained observation above), the capture will show what differs.

## R7. Declarative apply

- **Decision**: a NixOS module `hardware.aquaeroCtl` renders the desired state to a JSON file in the store and runs a systemd oneshot `aquaero-ctl-apply.service` on activation and when the device appears (the same udev `TAG+="systemd"` pattern as `modules/hardware-scarlett-mixer.nix`). Option `mode` is `"apply"` (default) or `"check"` (reports drift, never writes), per the clarification. Range checks run at evaluation time as module assertions (FR-016).
- **Exit codes**: the tool exits 0 when the device is already as desired and when it is absent (with a warning), so a missing device never fails a switch (FR-015); non-zero only for a real failure. Absent-device is mapped explicitly rather than hidden.
- **Alternatives rejected**: a long-running daemon (nothing needs polling; the device stores the curve); running only at boot (a changed config would not apply on switch).

## R8. Test strategy

- **Decision**: test-first, per the constitution. (1) Unit and property tests for curve validation and the encode/decode round trip. (2) Apply logic against the in-memory fake device with injected failures: rejected write, short read, disconnect mid-sequence, wrong firmware, read-back mismatch (SC-006). (3) Fixtures from real dumps, serial redacted, for the diff and profile tests. (4) Hardware tests are manual and named as untestable glue: the first real write, the power-cycle persistence check (SC-002) and the sensor-loss check (SC-009).
- **Dependencies for tests**: `proptest`, `tempfile`.

## R9. Packaging and layout

- **Decision**: one crate, `scripts/aquaero-ctl/`, a library plus a thin binary, built with `rustPlatform.buildRustPackage` in `pkgs/aquaero-ctl/default.nix` and `cargoLock.lockFile` (the repo's pattern in `pkgs/token-tools`), not crate2nix. The clippy `restriction` lint table from the programming skill is mandatory. The NixOS module is a single file `modules/hardware-aquaero-ctl.nix`, exported in `flake-modules/nixos-modules.nix`.
- **Alternative rejected**: crate2nix (not what this repo uses for its other Rust tools today).

## R10. Staged safety for the first real write

- **Decision**: with one device, the first writes are staged so each step proves the next: (1) write back the unchanged snapshot (no-op write: proves the write path and verify); (2) change one benign value (fan 4 minimum speed) and restore from the backup; (3) only then write the curve. Each stage needs the owner's explicit go-ahead in that session (constitution III: live changes by consent).
- **Recovery**: Aquasuite in the Windows VM remains the way to recover if the tool misconfigures the device. Keep the VM image until the tool has been proven.

## Open items carried into tasks

| Item | Needed by |
|------|-----------|
| Which `hidraw` node serves report 0x0B; what the wrong node returns | dump command |
| Firmware version of this device | profile, FR-006 |
| Where the curve, its points and sensor-loss behaviour live in the blob | story 2 |
| How many curve points and what resolution the device supports | curve validation |
| The save/commit sequence Aquasuite performs (USB capture) | story 2 |
| Why `pwm4` writes via the driver did not change fan 4 | confidence in the write path |
