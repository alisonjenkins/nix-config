# Quickstart: validating aquaero-ctl end to end

**Spec**: [spec.md](spec.md) | **Contracts**: [cli](contracts/cli.md), [nix module](contracts/nix-module.md)

Each scenario names the story and success criterion it proves. Scenarios 1 to 3 are read-only. Scenarios 4 to 7 write to the real device and each needs the owner's go-ahead in that session.

## Prerequisites

- The aquaero is connected to this host and **not** held by the Windows VM (a running VM takes the device away from Linux).
- Read access to the aquaero's `hidraw` node (the module's udev rule grants it; before the module exists, a one-off rule or `sudo`).
- The Windows VM image from the discovery sessions is kept until the tool is proven, as the recovery path.

## 1. Read-only snapshot (story 1, FR-001)

Take a snapshot twice with nothing changed in between. Expect: both succeed, the device is unchanged, firmware and length are reported, and `diff` of the two lists only volatile positions.

## 2. One setting, one diff (story 1, FR-002)

With the device on the VM: snapshot, change only fan 4's minimum speed in Aquasuite, snapshot, return the device to the host and `diff` with the untouched pair as baseline. Expect: a short list of differing positions, none of them volatile. Repeat with a second value; the same positions change.

## 3. Dry run (story 3, FR-009)

Run `plan` with a desired curve. Expect: each change listed with old and new values and byte positions; no backup file appears; the device is unchanged afterwards.

## 4. First real write, in three stages (story 3, SC-003, SC-005)

Stage A: apply a desired state equal to the current one by writing the unchanged snapshot back. Expect: backup saved, write, read-back match, device unchanged.
Stage B: change only fan 4's minimum speed, then `restore` the backup. Expect: byte-identical to the original snapshot (`diff` is empty).
Stage C: apply the real curve. Expect: backup path, writes and read-back result printed; `diff` against the backup shows only the in-scope positions.

## 5. Persistence and behaviour (story 2, SC-002, SC-007)

After stage C, power the whole machine off and on without starting any software. Expect: with the coolant held near the lower and the upper temperature, the fans, steady for 60 s, are within 5 points of the minimum and of full speed; a snapshot compared with the pre-change one differs only in scope.

## 6. Sensor loss (story 2, SC-009)

Disconnect the coolant sensor. Expect: the fans go to full speed, never below the minimum.

## 7. NixOS switch (story 4, SC-004, FR-014, FR-015)

Declare the curve, switch: the device matches. Switch again: the service reports nothing to change and writes nothing. Set `mode = "check"` with a changed curve: the switch succeeds, drift is logged and nothing is written. Unplug the device and switch: the switch still succeeds with a warning.

## 8. Failure injection (story 3, SC-006)

Run against the in-memory fake device (no hardware): rejected write, short read, disconnect mid-sequence, read-back mismatch, unknown firmware. Expect, for each: no unreported partial state; either the original or the intended configuration, or an error that names the backup and the restore command.

## Coexistence check (story 5, SC-008)

Throughout scenarios 4 to 7, read the driver's `hwmon` sensors before and after. Expect: the same sensors present with sensible values and no driver reload.
