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
| The whole stored configuration is HID feature report `0x0B`, 2707 (`0xa93`) bytes including the leading id | kernel driver | **verified on the device** (2026-10-13): a read returns 2707 bytes starting `0b`, served by the `hidraw` node of the `input2` interface (`/dev/hidraw1` that day) |
| A second feature report, id `6`, exists for system commands | vendor library | verified in the decompiled source: `SystemControl.SYSTEMCOMMAND_REPORTID = 6`; `SystemCommand` has `SaveSettings = 2`, `Reset = 1`, `LoadProfile = 4`, `FactoryReset = 5` |
| After each configuration write the host sends a 7-byte id-6 report, `06 00 02 00 00 00 00`, about 4.1 s after the 2707-byte report 0x0B | USB capture of a save (2026-10-13) | **observed** in one save, seen twice (finding 4). That the value 2 is `SaveSettings` is **inferred** |
| Per-fan control structs at `0x20c`, `0x220`, `0x234`, `0x248` (20 bytes each); min power at +4, max at +6, control source at +0x10 (big-endian 16 bits) | kernel driver | **struct positions consistent with the device**: before the firmware reflash channel 4, the configured radiator fans, differed from channels 1 to 3; after it all four structs held the same defaults (**observed**, finding 3). Field meanings inside the struct still unverified |
| Fan preset power, big-endian 16 bits, hundredths of a percent; preset 1 at `0x055c` (80% = `0x1f40`, 100% = `0x2710`) | USB capture and Aquasuite (2026-10-13) | **observed** for preset 1 (finding 5), matching the kernel driver's base `0x55c`; presets 2 to 4 unverified |
| Serial at `0x07` and firmware at `0x0b` (kernel driver's offsets) | kernel driver | **wrong for this device**: bytes `0x07..0x0b` are zero in the stored configuration. The serial is the USB serial (`HID_UNIQ`, `21998-56576` form `NNNNN-NNNNN`); the firmware is 2104 on Aquasuite's System page (**observed**, finding 1); no firmware field is located in the stored configuration |
| Bytes 1 and 2 of the report, big-endian, are the data version: `0x04b0` = 1200 | device | **verified**; equals the vendor library's `VALID_DATAVERSION`. A firmware profile is keyed on it |
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

## Controller layout (observed 2026-10-13)

Offsets are into the 2707-byte report 0x0B, including its leading id byte.
Multi-byte values are big-endian. Temperatures are in 0.01 °C and outputs in
0.01 %.

- **Method** (observed). Two dumps were taken, before and after Aquasuite (in the
  Windows VM) added "Curve controller 1", set its data source to Sensor 1, set its
  startup temperature to 31.7 °C and changed its third curve point's output from
  2.8 % to 3.6 %. The diff was five bytes: 0x061c..0x061f (`ff ff 0b b8` ->
  `00 00 0c 62`) and 0x0645 (0x18 -> 0x68).
- **Curve controller array** (observed). Four slots with a stride of 0x44 (68)
  bytes, at 0x061c, 0x0660, 0x06a4 and 0x06e8; the array ends at 0x072c. The four
  slots were identical default records. Slot layout:
  - +0x00: source, u16. 0xffff = no data source; Sensor 1 = 0x0000.
  - +0x02: startup temperature, u16. Default 0x0bb8 = 30.00 °C; 0x0c62 = 31.70 °C.
  - +0x04: sixteen temperatures, u16 each, ascending. Default 0x0a8c = 27.00 °C
    up to 0x0fa0 = 40.00 °C.
  - +0x24: sixteen outputs, u16 each. Default 0 up to 0x2710 = 100.00 %. The third
    output changed from 0x0118 (2.80 %) to 0x0168 (3.60 %) at 0x0645.

  A curve therefore has exactly 16 points.
- **Set-point controller array** (layout observed only as unchanged defaults; the
  role is inferred from Aquasuite's controller types). Eight records of 16 bytes
  from 0x059c: u16 source (0xffff), u16 target 0x0dac (35.00 °C), then 12 bytes
  `05 78 04 b0 00 00 00 28 00 14 00 01`. The meanings of the 12 bytes are unknown.
- **Preset controllers** (observed). The u16 power values from 0x055c (0x2710 =
  100.00 % each) are the preset controllers' power (see finding 5).
- **Two-point controller array** (inferred, unverified). Records from 0x072c with a
  repeating pattern beginning `00 0f ff 0f ff 07 d0 0f ff 0f ff 00 00 09 c4 0f a0
  02 09`. Probably the two-point controllers, since Aquasuite offers a "Two point
  controller" type.
- **Save behaviour** (observed). Aquasuite saves by itself shortly after a change:
  a save icon appears beside the aquaero entry in its sidebar while a change is
  pending, then disappears. One edit therefore produces one whole-configuration
  write.
- **Fan structs** (observed). The four per-fan structs at 0x020c, 0x0220, 0x0234
  and 0x0248 are identical after the factory reset. Field meanings beyond the
  kernel driver's min, max and source offsets are not yet verified.
- **Source numbering** (read from the vendor library's `SourceIndex` constants,
  `AquaComputerServiceLib.decompiled.cs` lines 87987 to 88000 and 88186 to 88198;
  matches the values seen on the device: Sensor 1 = 0, Preset 1 = 0x5c, preset 4
  = 0x5f). The 16-bit source in a fan struct or a controller record is a base
  plus a 0-based index: temperature sensors 0..63 (base 0), set-point controllers
  64..71 (base 0x40), two-point controllers 72..87 (base 0x48), curve controllers
  88..91 (base 0x58), preset values 92..123 (base 0x5c), RGB controllers 124..127
  (base 0x7c). So a fan driven by Curve controller 1 should hold 0x0058
  (**inferred** from the base plus index rule; not yet written to the device).
  Software sensors, fan amplifiers and flow sensors are not in the readable
  constants. The two-point controller array has 16 slots, not 4 or 8.

## Findings from the first captured save (2026-10-13)

Each finding is marked **observed** (seen on the real device, in the USB capture,
or on Aquasuite's screens) or **inferred** (not confirmed).

1. **Device model.** Aquasuite's System page shows "aquaero 5 PRO", firmware
   2104, serial 21998-56576, and "in standby mode, no 12 V power supply
   detected" (**observed**).
2. **Firmware image.** The firmware 2104 image (`aquaero5`, bootloader 100,
   hardware 5600, 659456 bytes) is stored in Aquasuite's SQLite database, table
   `firmware`, id 1 (**observed**). A copy is at
   `/home/ali/vms/aquasuite/backups/firmware/aquaero5-fw2104-bl100-hw5600.bin`,
   sha256 `97bde47308e022edd3620e48c6d1d680b3cd6313909d26fbb7305c5469e1566d`.
   A copy of the whole database is next to it. The image starts with 0xff bytes,
   so it is a raw flash image (**observed**). The chip cannot be read back, so
   this file is the one to reflash from (**observed**).
3. **Reflash and reset.** Aquasuite's "Update firmware now" reflashed 2104 over
   2104. It completed at 100%, and Aquasuite then asked to restart (**observed**).
   Afterwards the stored configuration differed from the dump taken before: 106
   bytes in 29 places, header unchanged (**observed**). All four fan structs hold
   the same defaults, all fans have control source 0x005c, and Aquasuite's
   Controllers page shows factory defaults: "Preset fan" at 100% driving fans 1
   to 4, "Preset relay", "Power outputs" (**observed**). Before the flash, fan 4
   was named "Radiator Fans" and driven by "Preset value 4" at 100%
   (**observed**). Whether the flash or Aquasuite's restart did the reset is
   unknown.
4. **The save sequence.** Captured with usbmon on the host while the Windows VM
   held the device. The sequence was seen twice, 28 s apart (the preset went
   from 100% to 80%, then back to 100%) (**observed**). Each save is one
   SET_FEATURE of report 0x0B, 2707 bytes (the whole configuration), then about
   4.1 s later one SET_FEATURE of report 0x06, 7 bytes: `06 00 02 00 00 00 00`
   (**observed**). Report 6 with value 2 matches the vendor library's
   `SystemCommand.SaveSettings = 2` (the link is **inferred**). The 4 s gap is
   part of the sequence to reproduce.
5. **Preset power offset.** Preset 1 ("Preset fan") power is at offset 0x055c,
   big-endian 16 bits, in hundredths of a percent: 80% = 0x1f40, 100% = 0x2710
   (**observed**). This matches the kernel driver's preset base 0x55c.
6. **Clock bytes.** Bytes 3 to 6 of the written configuration are a big-endian
   32-bit seconds counter: 0x21722ac2, then 0x21722ade 28 s later (**observed**).
   The device returns zeros there when read (**observed**). Aquasuite also sends
   a 7-byte report `06 90 88` followed by the same 4-byte counter at startup and
   later: 0x21722a54 at 47 s and 0x21722a77 at 83 s into the capture
   (**observed**). That this is a host clock sync is **inferred**, unconfirmed.
   A tool that writes should leave bytes 3 to 6 as read (zeros) and test that the
   device accepts it.
7. **Eleven bytes off by one.** Eleven bytes differ by one between what the
   device returned on read after the reflash and what Aquasuite wrote
   (**observed**). At offsets 0x062d, 0x063b, 0x0671, 0x067f, 0x06b5, 0x06c3,
   0x06f9 and 0x0707 the device has 0x9e or 0xf6 where Aquasuite wrote 0x9d or
   0xf5. At offsets 0x0748, 0x075d and 0x0772 the device has 0x0a where
   Aquasuite wrote 0x09. The same bytes changed by one in the opposite direction
   at the reflash. **Settled (observed, dump taken after Aquasuite's write):**
   the device keeps exactly what was written, including these eleven bytes
   (0x9d, 0xf5, 0x09). The only difference between that dump and the bytes
   Aquasuite wrote is bytes 3 to 6, which read as zeros. So a read-back check
   compares everything except bytes 3 to 6, and nothing else needs excusing.
8. **Other startup reports.** Aquasuite sends at startup report 0x04 (2114
   bytes) and three report 0x09 writes (1038 bytes each, beginning
   `09 01 00 09 40`, then `... 50` and `... 60`) (**observed**). Purpose unknown;
   not needed for fan control.
9. **Capture method.** usbmon needs root (**observed**). The capture used
   `sudo nix shell nixpkgs#wireshark-cli -c dumpcap -i usbmon1 -w - > FILE`. The
   shell redirect writes the file as the user, because dumpcap drops privileges.
   It was analysed with the tshark fields `usb.data_len` and
   `usb.data_fragment`. File: `/home/ali/vms/aquasuite/captures/save1.pcapng`.

## Open items

| Item | Settled by |
|------|-----------|
| Every byte offset and width in the 2707-byte report | snapshot diffs (T029) |
| Which fan source value means Curve controller 1 | snapshot diff with a fan set to Curve controller 1 (T029) |
| Set-point and two-point controller field meanings | snapshot diffs (T029) |
| What the fan does when its sensor is lost, and where that is stored | snapshot diffs (T029) |
| Why `pwm4` writes through the driver did not change fan 4's speed | experiment (T028) |
| Clock bytes 3 to 6 of the written configuration (finding 6): whether the device accepts zeros there | a write with zeros in those bytes, then a read-back check (T029) |
