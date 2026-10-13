# Configuring an aquaero from Linux

Working notes for `scripts/aquaero-ctl` and spec `specs/008-aquaero-linux-config/`.
They record how the stored-configuration layout is being learned, and what is
known, inferred and still unknown. Nothing here is verified against a device
until a finding says so.

## Why this exists

The aquaero's fan curves live in the device. Aqua Computer's software for
changing them runs only on Windows, and the in-tree Linux driver
(`aquacomputer_d5next`) reads sensors and sets a fixed PWM but cannot edit
curves. `aquaero-ctl` reads the device's configuration report over `hidraw`, and
will write it back, so the curve can be set without Windows.

## What is known about the protocol

| Fact | Source | Status |
|------|--------|--------|
| The whole stored configuration is HID feature report `0x0B`, 2707 (`0xa93`) bytes including the leading id | kernel driver | report id confirmed by the vendor library (`AquaeroSettings.SETTINGS_REPORTID = 11`); the length is unconfirmed |
| A second feature report, id `6`, exists for system commands | vendor library | verified in the decompiled source: `SystemControl.SYSTEMCOMMAND_REPORTID = 6`; `SystemCommand` has `SaveSettings = 2`, `Reset = 1`, `LoadProfile = 4`, `FactoryReset = 5` |
| The kernel driver sends a 7-byte id-6 report after every configuration write | kernel driver | inferred to be a system command, probably save; the bytes and the order are unconfirmed |
| Per-fan control structs at `0x20c`, `0x220`, `0x234`, `0x248` (20 bytes each); min power at +4, max at +6, control source at +0x10 (big-endian 16 bits) | kernel driver | unverified for this firmware |
| Fan preset power (hundredths of a percent) from `0x55c`, 2 bytes per fan | kernel driver | unverified |
| Serial: two big-endian 16-bit numbers at `0x07` and `0x09`, shown `NNNNN-NNNNN`; firmware: big-endian 16 bits at `0x0b` | kernel driver | the form matches what the vendor installer shows; the offsets are unverified |
| The vendor library expects aquaero firmware `2104` and data version `1200` | vendor library | verified in the decompiled source (`Aquaero5.VALID_FIRMWARE`, `VALID_DATAVERSION`) |
| No checksum is needed for the aquaero configuration report | kernel driver | unverified |

## Discovery environment

- A Windows 10 VM built with `quickemu` (`windows-10.conf`), with the aquaero
  passed through over USB. **A running VM takes the device away from Linux**:
  `hidraw` and the `hwmon` driver see nothing until it is shut down.
- Aquasuite X.79 and the .NET 8 Desktop Runtime are installed in it. X.79 was
  chosen because the device's update service covers it; X.94 needs a paid
  extension. The vendor's setup is a web downloader that lists the connected
  devices and offers the versions they are licensed for, so it must run with the
  device attached.
- The installed files were copied out to the host for analysis. They, and
  anything decompiled from them, stay outside this repository: only findings
  are recorded here.
- The guest is driven over VNC (`-vnc 127.0.0.1:1`). The guest's Caps Lock is
  stuck on and the VNC key map drops Shift for symbols, so typing works by
  swapping the case of letters and sending `shift-;` for a colon. A small HTTP
  server on the host (reachable from the guest at `10.0.2.2`) serves scripts to
  the guest and accepts uploads.

## Static analysis of the vendor software

Command used, repeatable: `ilspycmd -o OUT <assembly>` (nixpkgs `ilspycmd`,
version 9.1) on `AquaComputerServiceLib.dll` and `AquaComputerCmd.exe`.

`rea`'s managed provider stopped at its 64 MiB metadata budget on the library
and returned partial coverage, so the decompiler was used instead.

The assemblies carry a commercial protector (anti-tamper and debugger checks).
They were only read, never run or debugged, and no protection was defeated.

### What is readable

Public type, member and constant names. The library decompiles to about 159,000
lines. About 14,600 methods are empty stubs: their bodies were removed by the
protector.

### What is not

The code that turns the settings model into the 2707-byte report. Verified:
`AquaeroSettings.BufferToData` and `WriteData` are empty, no `0xa93`/2707
literal exists anywhere in the library, and the only `GetFeatureReport` /
`SetFeatureReport` entries are declarations. **Byte offsets cannot be recovered
from this source.** They have to come from snapshot diffs and a USB capture.

### What the names and constants tell us

Verified against the source unless marked.

- The aquaero model is `Aquaero5Base` and `IAquaero5Settings`, class `Aquaero5`.
- `FanConfiguration` (aquaero namespace) has power minimum, maximum and start,
  rpm minimum and maximum, a current limit, a start-up time, a calibration, a
  data source, a control mode (`POWERCONTROLLED`, `RPMCONTROLLED`,
  `PWMCONTROLLED`), a step mode and flags (`HoldMinPower`, `LimitCurrent`,
  `UseStartburst`). Units and ranges are runtime data and not visible.
- *From the sub-agent's reading, not independently checked:* the model has 12
  fans, 4 curve controllers, 8 set-point and 16 two-point controllers, 32
  constants and 64 temperature sensors, sharing one numbering of "data sources"
  (sensors from 0, set-points at 64, two-point at 72, curves at 88, constants at
  92); a fan refers to its controller through its source id. A curve controller
  (`CurveControllerConfiguration`) holds a start temperature, a source, and
  arrays of temperatures and powers. The number of curve points is not visible.
- *Not verified:* a "power when the sensor is lost" field was not found for the
  fans. A sensor-not-available marker, 32767, appears in data reports.

### A correction

`FanSetup`, `ControllerSetup`, `ControllerCurve` and `SensorCurve` are not the
aquaero's settings model. They belong to the Quadro, Octo, D5 Next and
Aquastream Ultimate namespaces. The aquaero uses `FanConfiguration` and
`CurveControllerConfiguration`.

## Open items

| Item | Settled by |
|------|-----------|
| Which `hidrawN` carries report 0x0B; the device's real firmware version and serial offsets | reading a snapshot (T025) |
| Every byte offset and width in the 2707-byte report | snapshot diffs (T029) |
| The number of curve points; units and resolution of temperature and power | snapshot diffs (T029) |
| What the fan does when its sensor is lost, and where that is stored | snapshot diffs (T029) |
| The exact bytes of the id-6 report and whether it is sent after the id-11 write | USB capture of a save (T030) |
| Why `pwm4` writes through the driver did not change fan 4's speed | experiment (T028) |
