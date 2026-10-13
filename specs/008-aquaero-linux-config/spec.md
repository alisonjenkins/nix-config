# Feature Specification: Aquaero Fan Controller Configuration on Linux

**Feature Branch**: `008-aquaero-linux-config`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Native Linux tool, written in Rust, to configure an Aquacomputer aquaero fan controller without Windows or Aquasuite. Today the aquaero can only be configured from Windows software, so a Linux-only owner cannot set fan curves; the in-tree kernel driver (aquacomputer_d5next) only reads sensors and sets fixed PWM. The tool must read the device's configuration blob (HID feature report 0x0B, 0xa93 bytes) via hidraw, back it up, and set a coolant-temperature-driven fan curve with a minimum speed for one fan channel (fan 4, radiator fans, driven by Sensor 1 coolant temperature), persisted in the device so it works without the PC. It must be userland (not a kernel module), safe against bricking (read-only dump first, backup, firmware-version check, dry-run diff, verify by re-read, restore command), coexist with the loaded kernel driver, and be applied declaratively from the NixOS config. The protocol layout is to be reverse engineered by diffing configuration dumps while changing one Aquasuite setting at a time in a Windows VM with the device passed through."

## Clarifications

### Session 2026-10-13

- Q: If the device loses the curve on power loss, what should v1 do? → A: Not a case to handle. The device retains its configuration across power loss (owners already configure once in Windows and then run Linux), and the aim is to remove the Windows requirement altogether, so persistence is required and there is no boot-time re-apply fallback.
- Q: Should the NixOS switch write to the device on its own? → A: Yes by default (with backup, firmware check and read-back), but a per-host option makes a host check-only, where the switch reports drift and writes nothing.
- Q: How close counts as the fans following the curve? → A: Within ±5 percentage points of the curve's target speed once settled, where settled means steady for 60 seconds.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Learn what each setting does, from the device itself (Priority: P1)

The owner has an aquaero whose settings can only be changed from Windows. Before anything is written from Linux, the owner needs to know, for each setting in scope, exactly which part of the device's stored configuration it controls. They get this by taking a snapshot of the device's configuration, changing one setting at a time in the vendor's Windows software (in a virtual machine with the device passed through), taking another snapshot, and comparing the two. The result is a recorded map from each in-scope setting to the stored bytes that hold it.

**Why this priority**: Every later capability depends on this map. Writing without it is guessing at a device that holds the owner's cooling-loop control.

**Independent Test**: With the device on the host, take a snapshot and confirm it is read-only (the device's behaviour is unchanged afterwards). Then, for one setting (for example fan 4's minimum speed), change only that setting in the Windows software, snapshot again, and see a comparison that isolates the changed bytes and nothing else.

**Acceptance Scenarios**:

1. **Given** the device is connected and the tool has permission to reach it, **When** the owner takes a snapshot, **Then** the full stored configuration is saved with the device's firmware version and a timestamp, and nothing on the device changes.
2. **Given** two snapshots that differ by exactly one setting changed in the vendor software, **When** the owner compares them, **Then** the comparison lists only the differing positions and their old and new values.
3. **Given** the same setting changed to two different values, **When** both snapshots are compared against the baseline, **Then** the changed positions are the same in both and the values follow the setting.
4. **Given** a snapshot taken twice with no setting changed in between, **When** compared, **Then** any differences are flagged as volatile so they are not mistaken for settings.

---

### User Story 2 - Set a coolant-driven fan curve from Linux (Priority: P1)

The owner runs one command on Linux and the radiator fans (fan channel 4) are set to follow the coolant temperature (Sensor 1): a minimum speed at and below a low temperature, rising to full speed at a high temperature, with the shape defined by the owner. The setting is stored in the device, so the fans keep following the curve when the PC is off, asleep, or has no software running.

**Why this priority**: This is the whole point. Today the radiator fans run flat out because nothing configures the controller.

**Independent Test**: Apply a curve (for example 30% minimum up to 100% at 45°C), power-cycle the whole machine without starting any software, and watch the fan speed track the coolant temperature while the PC is on.

**Acceptance Scenarios**:

1. **Given** an unconfigured device with the radiator fans at full speed, **When** the owner applies a curve of 30% minimum rising to 100% at 45°C, **Then** once settled (steady for 60 seconds) the fans are within 5 percentage points of the curve's target: at 31°C coolant near the minimum, and at 45°C or above at full speed.
2. **Given** the curve has been applied, **When** the machine is fully powered off and on again without starting any software, **Then** the fans still follow the curve.
3. **Given** the curve has been applied, **When** the owner reads the configuration back, **Then** it reports the curve's points, the minimum speed, the controlling sensor and the fan channel exactly as set.
4. **Given** the coolant sensor reading is lost, **When** the controller cannot read it, **Then** the fans go to full speed rather than stall or hold the last value.
5. **Given** the owner's settings for channels and features outside the scope of this feature, **When** a curve is applied, **Then** those settings are unchanged, byte for byte.

---

### User Story 3 - Never leave the controller worse off (Priority: P1)

Writing to a controller that manages a water loop is risky. Every change must be reversible, previewable and verified. The owner can see exactly what would change before it happens, is protected against applying a change to a firmware the tool does not understand, has an automatic backup of what was there, can verify what was written, and can put the device back to exactly how it was.

**Why this priority**: A wrong write can misconfigure or brick the device. The tool is only acceptable if its failure modes are bounded.

**Independent Test**: Apply a change, then restore from the automatic backup, and confirm the stored configuration is byte-identical to the original snapshot. Separately, run against a device reporting an unknown firmware version and confirm the tool refuses to write.

**Acceptance Scenarios**:

1. **Given** a desired curve, **When** the owner asks for a dry run, **Then** the tool shows each setting that would change (old and new value) and writes nothing.
2. **Given** a real apply, **When** it starts, **Then** a backup of the full current configuration is saved before any write.
3. **Given** a write has completed, **When** the tool reads the configuration back, **Then** it confirms the stored values equal the intended ones, and reports failure otherwise.
4. **Given** a device reporting a firmware version the tool has no known layout for, **When** the owner tries to apply, **Then** the tool refuses and says which firmware versions it knows.
5. **Given** a backup, **When** the owner restores it, **Then** the stored configuration returns to the backup's contents and the tool confirms by reading back.
6. **Given** the device is disconnected or rejects the write part-way, **When** the tool detects it, **Then** it reports the failure, states the device's last known state, and tells the owner how to restore.

---

### User Story 4 - Apply the curve declaratively from the NixOS config (Priority: P2)

The owner states the desired curve in their NixOS configuration, switches, and the device ends up with that curve. Running it again changes nothing. Changing the curve in the configuration and switching updates the device.

**Why this priority**: The owner manages every machine from this repository, and a hand-run command would drift. It builds on the working, safe tool from stories 2 and 3.

**Independent Test**: Set a curve in the configuration, switch, and read the device back to see it. Switch again with no change and confirm no write happens. Change one value, switch, and confirm only that value changed on the device.

**Acceptance Scenarios**:

1. **Given** a curve declared in the configuration and a device with a different curve, **When** the owner switches, **Then** the device ends up with the declared curve.
2. **Given** the device already matches the declared curve, **When** the owner switches again, **Then** the tool performs no write.
3. **Given** the device is absent at activation (unplugged), **When** the owner switches, **Then** the system activation still succeeds and the missing device is reported clearly.
4. **Given** a declared curve that is out of range (for example a minimum above full speed), **When** the owner builds the configuration, **Then** the build fails with a message naming the invalid value.
5. **Given** a host set to check-only and a device that differs from the declared curve, **When** the owner switches, **Then** the switch reports the drift, writes nothing, and still succeeds.

---

### User Story 5 - Coexist with the existing kernel driver and normal monitoring (Priority: P2)

The owner already reads coolant temperature, fan speeds and flow through the in-tree kernel driver. Using the new tool must not break that monitoring, and the driver must not undo what the tool wrote.

**Why this priority**: The owner's monitoring and any fixed-speed writes through the driver keep working during and after configuration.

**Independent Test**: With the driver loaded, snapshot, apply a curve and read the monitoring values before and after: the same sensors are present and report sensible values, and the applied curve is still in place after a monitoring read.

**Acceptance Scenarios**:

1. **Given** the kernel driver is loaded, **When** the owner applies a curve, **Then** the driver's sensors keep reporting afterwards without a reload.
2. **Given** a curve is applied, **When** the owner reads monitoring values through the driver, **Then** reading does not alter the stored configuration.
3. **Given** the tool is about to write, **When** another writer (the driver's fixed-speed write) is active, **Then** the tool detects it or documents that it must not run together, and does not silently interleave writes.

---

### User Story 6 - Record what was learned so it can be reused (Priority: P3)

The mapping from settings to stored bytes, the firmware versions it was verified on, and the surprises found along the way are written down, so another owner (or the kernel driver and liquidctl maintainers) can reuse them.

**Why this priority**: The knowledge is the lasting product, and the repository's practice is to record hard-won findings next to the change.

**Independent Test**: A reader with a different aquaero of a recorded firmware version can follow the record and reproduce the same setting-to-bytes mapping.

**Acceptance Scenarios**:

1. **Given** the mapping is established, **When** the feature is delivered, **Then** a document lists each in-scope setting, where it is stored, its encoding, and the firmware versions verified.
2. **Given** a non-obvious finding (for example whether settings persist in the device), **When** it is learned, **Then** it is recorded with the evidence that showed it.

---

### Edge Cases

- The device reports a firmware version with no known layout: no write is attempted.
- The device is unplugged, or the machine loses power, in the middle of a write: the tool reports what it knows; restore from the backup brings the device back, and no half-written state is left unreported.
- A write is accepted but a read-back differs: reported as a failure with both values shown.
- A write reads back correctly but is lost after a full power cycle: this is a defect in how the tool stores settings (for example a missing commit step), caught by the power-cycle test in SC-002, not a case the tool works around.
- More than one aquaero is connected: the tool requires the owner to pick a device explicitly rather than choosing one.
- The tool lacks permission to reach the device: a clear message says what access is missing.
- The owner's configuration already contains non-default settings made in the vendor software: they are preserved untouched.
- Two snapshots differ in places unrelated to any setting (counters, timestamps): these are shown as volatile in comparisons.
- The coolant sensor is missing or reads an impossible value: the fans must not stall; they go to full speed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST read the device's full stored configuration without changing it and save it as a snapshot labelled with the device's firmware version and a UTC timestamp.
- **FR-002**: The tool MUST compare two snapshots and list the differing positions with old and new values, marking positions that differ between two untouched snapshots as volatile.
- **FR-003**: The tool MUST set, for the radiator fan channel (fan 4), a curve of fan speed against the coolant temperature (Sensor 1), including a minimum speed and a speed at each curve point.
- **FR-004**: The stored curve MUST be retained by the device so that the fans keep following it when no software is running on the PC.
- **FR-005**: A change MUST alter only the settings in scope; every other stored byte MUST be left as it was.
- **FR-006**: The tool MUST refuse to write to a firmware version it has no verified layout for, and MUST name the versions it knows.
- **FR-007**: The tool MUST save a backup of the full current configuration before any write, and MUST NOT write if the backup cannot be saved.
- **FR-008**: After every write the tool MUST read the configuration back and report whether the stored values equal the intended ones.
- **FR-009**: The tool MUST offer a dry run that shows what would change and writes nothing.
- **FR-010**: The tool MUST offer a restore that returns the device to a chosen backup and verifies it by reading back.
- **FR-011**: A curve MUST define the behaviour when the coolant reading is lost, and that behaviour MUST be full fan speed.
- **FR-012**: Reading and writing MUST work while the in-tree kernel driver is loaded, without unloading it.
- **FR-013**: The tool MUST NOT run as, or require, a kernel module.
- **FR-014**: The desired curve MUST be declarable in the NixOS configuration and applied on switch, idempotently (no write when the device already matches). A per-host option MUST make the switch check-only: it reports drift and never writes.
- **FR-015**: A missing device at activation MUST NOT fail the system switch; it MUST be reported.
- **FR-016**: Values out of range (negative speeds, a minimum above 100%, a curve that does not rise with temperature) MUST be rejected before any write, with a message naming the value.
- **FR-017**: Errors MUST name the failing operation and the inputs involved (device, report, position), not just a status code.
- **FR-018**: With more than one device present, the tool MUST require an explicit choice of device.
- **FR-019**: The mapping from each in-scope setting to its stored position and encoding, with the firmware versions it was verified on, MUST be recorded in the repository's documentation.

### Key Entities

- **Device**: One aquaero fan controller, identified by its hardware address and serial number, reporting a firmware version.
- **Configuration snapshot**: The device's full stored configuration at a moment in time, with firmware version, timestamp and an optional label. Snapshots are the unit of backup, comparison and restore.
- **Firmware profile**: A verified description of where each in-scope setting lives for one firmware version. A device is writable only if a profile exists for its version.
- **Fan curve**: For one fan channel: the controlling temperature sensor, the minimum speed, the temperature-to-speed points, and the behaviour on sensor loss.
- **Desired state**: The curve the owner declares in the system configuration, compared against the device to decide whether any write is needed.
- **Backup**: A snapshot saved automatically before a write, used by restore.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An owner with no Windows machine can set the radiator fan curve and see it applied in under 5 minutes of hands-on time, using only Linux.
- **SC-002**: After a full power-off and power-on with no software started, the radiator fans, once steady for 60 seconds, are within 5 percentage points of full speed at the curve's upper temperature and of the minimum at or below its lower temperature, in a test with the coolant held at those temperatures.
- **SC-003**: 100% of writes are preceded by a saved backup and followed by a read-back check, shown in the tool's output for every apply.
- **SC-004**: Applying the same curve twice results in zero writes the second time.
- **SC-005**: Restoring a backup returns the stored configuration to a state byte-identical to the backup in every test run.
- **SC-006**: In every injected failure tested (device unplugged mid-write, write rejected, unknown firmware), the device ends in either its original configuration or the intended one, or the owner is told exactly how to restore, with no unreported partial state.
- **SC-007**: After applying a curve, no setting outside the scope differs from the pre-change snapshot, checked by comparing snapshots.
- **SC-008**: The owner's existing temperature, fan-speed and flow monitoring keeps reporting with no reload after a curve is applied.
- **SC-009**: Fan speed never drops below the configured minimum, and under sensor loss goes to full speed, in a test that disconnects the coolant sensor.

## Assumptions

- **Owner decisions carried from the request**: the tool runs in user space (not a kernel module), is written in Rust, is built and applied through the Nix configuration, and is a separate tool from the kernel driver.
- **Device**: the owner's single aquaero (believed to be an Aquaero 6 LT, four fan channels) is the target. The pump is not connected to it, so fan channel 4 drives only the radiator fans. Its firmware version is to be read, not assumed.
- **Scope for the first version**: one fan channel (4) and one temperature source (Sensor 1). Other channels, lighting, display, alarms and other settings are out of scope and left untouched.
- **Reverse engineering method**: the vendor's Windows software runs in a virtual machine with the device passed through, and the stored configuration is snapshotted before and after each single-setting change. This is used only for discovery; the finished tool does not need Windows.
- **Persistence is established**: the device retains its stored configuration across power loss, which is how owners configure it once in Windows and then run it from Linux. The tool writes to that persistent store, so no boot-time re-apply is needed.
- **No Windows in the end state**: the Windows virtual machine is needed only once, to discover the layout. The finished tool configures the device with no Windows machine, virtual or physical.
- **Existing knowledge**: the kernel driver already reads and writes the same configuration region without a checksum for this device, and community projects have partial layouts; these are starting points to verify, not facts to trust.
- **Safety limits accepted**: only firmware versions with a verified profile are writable; the vendor software remains the way to recover if everything else fails.
- **Licensing**: reverse engineering is for interoperability with the owner's own hardware; the vendor's licence terms are not yet reviewed.
- **Out of scope**: replacing the vendor software wholesale, supporting devices other than the aquaero, and a graphical interface.
