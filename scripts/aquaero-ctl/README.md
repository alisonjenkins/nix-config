# aquaero-ctl

Read, compare and set the stored configuration of an Aquacomputer aquaero fan
controller from Linux. It reads (`dump`, `diff`, `show`, `plan`,
`list-backups`) and sets a fan curve (`apply`, `restore`); see
`specs/008-aquaero-linux-config/`.

It talks to the device through its `hidraw` node, from user space, and works
beside the kernel's `aquacomputer_d5next` driver without unloading it.

## Commands

```
aquaero-ctl dump --out DIR [--label TEXT] [--redact-serial]
aquaero-ctl diff A.bin B.bin [--baseline C.bin]
aquaero-ctl show [--snapshot SNAP.bin]
aquaero-ctl plan --desired FILE [--snapshot SNAP.bin]
aquaero-ctl apply --desired FILE [--check] [--fail-on-drift] [--backup-dir DIR]
aquaero-ctl restore SNAP.bin [--yes] [--backup-dir DIR]
aquaero-ctl list-backups [--backup-dir DIR]
```

- `dump` saves the device's configuration as `DIR/<UTC time>-<label>.bin` (the
  raw 2707 bytes) and a `.json` beside it (serial, firmware, time, SHA-256).
  It only reads from the device, and it never overwrites an existing snapshot.
- `diff` lists the bytes that differ between two snapshots, as hex runs. Give
  `--baseline C.bin`, a second snapshot of the same untouched state as `A`, and
  positions that changed on their own (counters, timestamps) are marked
  `(volatile)`, so they are not mistaken for settings.
- `show` decodes the settings this tool manages (every fan and curve controller)
  from the device, or offline from `--snapshot`. It needs a profile for the
  configuration's data version, and exits 3 naming the known versions if there
  is none.
- `plan` is a dry run: it reads the device (or `--snapshot`) and prints one line
  per change, `name: old -> new (bytes 0x024c..0x024e)`, then
  `N changes; every other byte is unchanged` or
  `already as desired; nothing to write`. It never writes and never saves a
  backup. `--json` gives `changes` (`name`, `old`, `new`, `positions` as
  `[start, end]` pairs), `already_applied` and `untouched_equal`.
- `apply` reads the desired-state JSON first (exit 2 if it is invalid), then
  plans against the device and, unless it is a check, backs up the current
  configuration, writes the new one, tells the device to keep it and reads it
  back. It prints, in order: `profile:` (data version and the firmware the
  layout was verified on), then either `already as desired; nothing written`,
  or the `drift:` lines (check mode), or `backup:` with the path of the `.bin`,
  one `wrote:` line per change, `saved:` and `read-back:`.
  - Check mode is `--check` or `"mode": "check"` in the file. It writes nothing
    and saves no backup. `--fail-on-drift` makes it exit 10 when the device
    differs.
  - With no aquaero connected, `apply` prints a warning on stderr and exits 0,
    so a missing device never fails a system switch. Every other command exits
    1 in that case.
  - The file's `device_serial` picks the device when `--serial` is not given.
  - It takes the device lock for the whole sequence.
- `restore` writes a snapshot back and reads it back to verify. It needs a
  profile for the snapshot's own data version (exit 3 otherwise), and refuses a
  snapshot from another device (exit 2) or another data version than the
  device's (exit 3). On a terminal it asks `restore <path> to the device?
  [y/N]` and aborts with exit 1 unless the answer is `y`; without a terminal it
  refuses with exit 2 unless `--yes` is given. It saves a backup of the
  configuration it replaces and prints its path.
- `list-backups` lists the `.json` sidecars in the backup directory, newest
  first: time taken, label, serial, data version and the `.bin` path. `--serial`
  filters; `--json` prints an array. It does not touch the device. An empty or
  missing directory prints `no backups`.

### Backup directory

`apply` and `restore` save the previous configuration, and `list-backups`
reads them, from `--backup-dir` or else:

1. `$STATE_DIRECTORY/backups` (set by systemd for a unit with `StateDirectory=`)
2. `$XDG_STATE_HOME/aquaero-ctl/backups`
3. `$HOME/.local/state/aquaero-ctl/backups`

A missing directory is created when the first backup is written. Backup names
start with the UTC time (`20261013T095012Z-pre-apply.bin`), so they sort in
time order. If a write fails after the device was touched, the error says where
the backup is and the `restore` command that puts it back.

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
| 0 | success, including "already as desired" and, for `apply` only, no device connected (a warning on stderr) |
| 1 | an error; the message names the operation and the path. Also: `restore` declined at the prompt |
| 2 | bad command line, invalid or unreadable desired state or curve, `restore` without `--yes` and without a terminal, or a snapshot from another device |
| 3 | no profile for this configuration's data version, or the snapshot's differs from the device's |
| 4 | more than one aquaero, or the serial given matches none |
| 5 | no hidraw node could be opened for lack of permission |
| 6 | the write was rejected, the save failed, or the read-back failed or differs; the message names the backup and the restore command |
| 7 | another aquaero-ctl holds the lock |
| 10 | drift found, only with `apply --check --fail-on-drift` |

## Committing a snapshot

A snapshot's `.json` holds the device's serial number (it is the USB serial;
the 2707 bytes in the `.bin` do not contain it, observed). Use `--redact-serial`
to clear it in the metadata before committing a snapshot. The fixtures under
`tests/fixtures/` are committed as bare `.bin` files for that reason.

## Development

```
nix develop ./scripts/aquaero-ctl   # cargo, clippy, rustfmt
cargo test
nix build .#aquaero-ctl             # also runs cargo fmt --check and clippy -D warnings
```
