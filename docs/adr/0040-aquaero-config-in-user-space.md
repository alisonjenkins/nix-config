# 0040. Configure the aquaero from user space, not from a kernel module

- Status: Accepted. The tool reads the device, and its write path is covered by tests against a fake device. The first write to the real device has not been made (the owner's go-ahead is pending).
- Date: 2026-10-13

## Context

The owner's aquaero (an aquaero 5 PRO, firmware 2104, USB `0c70:f001`) drives the radiator fans (fan 4) from a coolant sensor (Sensor 1). The vendor software that edits the curve is Windows-only. The kernel driver `aquacomputer_d5next` is loaded and exposes read-only sensors plus `pwm` writes for the aquaero. It cannot edit curves.

The device stores its configuration (curves, controllers) itself, so a curve written once keeps working with no software running. Observed: the owner configured it once in Windows and then moved to Linux, and the fans kept following the curve.

An earlier attempt to drive fan 4 from the host with fan2go failed. Its calibration sweep ran despite the configured min and max PWM, and PWM writes did not move fan 4 (observed). That module was dropped.

## Decision

A user-space Rust tool, `aquaero-ctl` (`scripts/aquaero-ctl/`), talks to the device through `hidraw` feature reports. There is no vendor library and no kernel patch. It reads and writes the whole stored configuration (HID feature report `0x0B`, 2707 bytes), then sends the save command (report 6, `06 00 02 00 00 00 00`, about 4.1 s after the write). It works beside the loaded kernel driver without unbinding it.

Every write is preceded by a backup of the previous configuration. Each write uses a firmware profile (data-driven TOML, keyed on the configuration data version at header bytes 1 and 2, 1200 on this device) and is verified by reading back. The read-back ignores bytes 3 to 6, a host clock the device never keeps (observed: it returns zeros there).

The NixOS module `hardware.aquaeroCtl` runs the tool declaratively. On the owner's desktop it starts in check mode: it reports drift and never writes.

How the layout was found:

- Decompiling the Aquasuite service library gave names, enums and constants only. The bodies of the serialising methods are stripped by a protector. No protection was defeated.
- Snapshot diffs of dumps taken before and after single changes made in Aquasuite, inside a Windows VM.
- One USB capture (usbmon) of a save, which gave the report sequence.

Verified on the device (observed): curve controllers are 4 records of 0x44 bytes at 0x061c (source u16, start temperature u16, 16 temperatures, 16 outputs, in 0.01 degC and 0.01 %). Source numbers come from the vendor's `SourceIndex` constants (Sensor 1 = 0, curve controller 1 = 0x58, presets from 0x5c). Fan structs are at 0x20c with a 0x14 stride (min power at +4, max at +6, source at +0x10). The offsets, the capture and the open items are in [`docs/aquaero-config.md`](../aquaero-config.md); the tables are not repeated here.

That the report 6 value 2 is the vendor's `SaveSettings` is inferred, not confirmed.

## Alternatives rejected

- **A kernel module, or a patch to the in-tree driver.** The driver's aquaero support exposes sensors and PWM only. A curve stored in the device needs the whole-configuration write. User space needs no kernel rebuild and can be tested against a fake device. Upstreaming the layout can follow.
- **A host-side curve with fan2go or a daemon.** It needs software running, and it failed in practice (see Context).
- **Running the vendor software in a VM permanently.** The point is to drop the Windows requirement.
- **A Rust crate or library wrapping libhid.** The ioctls are two calls.

## Consequences

- Only firmware profiles that were verified on a device are writable. Others exit 3.
- Version 1 supports fan 4 with Sensor 1 only, and uses curve controller 1.
- Aquasuite's own firmware update reset the stored configuration to factory defaults on the owner's device (observed: a reflash of 2104 over 2104 rewrote 106 bytes and cleared the fan 4 settings). Re-run the module after any firmware update. Do the first write knowing this.
- A wrong write could leave the device in a state that needs the vendor software or a firmware reflash to repair. A copy of the 2104 firmware image and the original configuration dumps are kept.
- Sensor-loss behaviour of a curve controller is not located yet, so the 100 % fallback in the spec (FR-011) is not implemented.
- Whether a controller output of exactly 0 switches a fan off is unconfirmed, so the tool never writes an output below 0.01 %.
- The udev permission rule gives only the service user (and optionally the logged-in desktop user) access to the one device.
- Writes from the kernel driver (`pwmN`) cannot be locked from user space. The read-back catches a mismatch but does not prevent the interleave.

## Evidence

- `docs/aquaero-config.md`: findings 1 to 9, the controller layout, and the USB capture of a save.
- `specs/008-aquaero-linux-config/research.md`: the analysis of the driver and the staged first write (R10).
- Tests against the fake device in `scripts/aquaero-ctl/tests/`.

## Revisit when

The first write to the real device is rejected or does not persist across a power cycle, or a second firmware version needs a profile that the keyed layout cannot express.
