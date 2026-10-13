# aquaero-ctl

Read and compare the stored configuration of an Aquacomputer aquaero fan
controller from Linux. This version only reads: `dump` and `diff`. Setting a
fan curve comes later (see `specs/008-aquaero-linux-config/`).

It talks to the device through its `hidraw` node, from user space, and works
beside the kernel's `aquacomputer_d5next` driver without unloading it.

## Commands

```
aquaero-ctl dump --out DIR [--label TEXT] [--redact-serial]
aquaero-ctl diff A.bin B.bin [--baseline C.bin]
```

- `dump` saves the device's configuration as `DIR/<UTC time>-<label>.bin` (the
  raw 2707 bytes) and a `.json` beside it (serial, firmware, time, SHA-256).
  It only reads from the device, and it never overwrites an existing snapshot.
- `diff` lists the bytes that differ between two snapshots, as hex runs. Give
  `--baseline C.bin`, a second snapshot of the same untouched state as `A`, and
  positions that changed on their own (counters, timestamps) are marked
  `(volatile)`, so they are not mistaken for settings.

Global options: `--json` for machine-readable output, `-v`/`-vv` for logging,
`--serial` to pick a device when more than one is connected, `--hidraw PATH` to
skip the search, `--lock-file PATH` (default `$XDG_RUNTIME_DIR/aquaero-ctl.lock`
when the session has a runtime directory, else `/run/aquaero-ctl.lock`).

## Access to the device

The `hidraw` node is root-owned by default. Either run with `sudo`, or give
your login session access with a udev rule:

```
# /etc/udev/rules.d/70-aquaero.rules
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0c70", ATTRS{idProduct}=="f001", TAG+="uaccess"
```

The lock file defaults to your user runtime directory, so no root is needed.
Runs as root and as a user use different lock files unless you pass the same
`--lock-file` to both.

A running Windows VM with the aquaero passed through takes the device away
from Linux; shut it down first.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | an error; the message names the operation and the path |
| 2 | bad command line |
| 4 | more than one aquaero, or the serial given matches none |
| 5 | no hidraw node could be opened for lack of permission |
| 7 | another aquaero-ctl holds the lock |

## Committing a snapshot

A snapshot contains the device's serial number. Use `--redact-serial` before
committing one. It clears the serial in the metadata and zeroes the serial
bytes, using the kernel driver's offsets, which are unverified until the
hardware tasks confirm them: check the file before committing it.

## Development

```
nix develop ./scripts/aquaero-ctl   # cargo, clippy, rustfmt
cargo test
nix build .#aquaero-ctl             # also runs cargo fmt --check and clippy -D warnings
```
