# Contract: `aquaero-ctl` command line

**Spec**: [../spec.md](../spec.md) | **Data model**: [../data-model.md](../data-model.md)

All times ISO 8601 UTC. Human output goes to stdout, diagnostics to stderr. `--json` gives machine-readable output for every command that reports.

## Global options

| Option | Meaning |
|--------|---------|
| `--serial <serial>` | Pick the device. Required when more than one aquaero is present (FR-018). |
| `--hidraw <path>` | Use this node instead of discovery (diagnostics only). |
| `--json` | Machine-readable output. |
| `-v` / `-vv` | More logging on stderr. |

## Commands

### `dump --out <path> [--label <text>]` (read-only)

Reads report 0x0B and writes a snapshot (`.bin` and `.json`). Prints the path, serial (redacted with `--redact-serial`), firmware, length and hash. Changes nothing on the device.

### `diff <a> <b>` (no device access)

Compares two snapshots. Prints each differing run: offset, before, after. Takes `--baseline <c>` (a third snapshot of the untouched device) to mark volatile positions.

### `show [--snapshot <path>]`

Decodes the in-scope settings (needs a profile for the firmware; says so and exits 3 if there is none).

### `plan --desired <file.json>` (read-only)

Dry run (FR-009). Prints each setting that would change with old and new values and the byte positions touched. Writes nothing and saves no backup.

### `apply --desired <file.json> [--check]`

1. Read the device and refuse if no profile matches the firmware (exit 3).
2. Validate the desired state before any access that writes (exit 2 on invalid values).
3. Compute the plan. If nothing changes, report that and exit 0 without writing (SC-004).
4. With `--check`, print the plan as drift and exit 0 (or 10 if there is drift and `--fail-on-drift` was given). Write nothing.
5. Otherwise save a backup, write, read back, and compare. Report success or the mismatch.

Takes the advisory lock for the whole sequence. Waits at least 200 ms between control operations.

### `restore <snapshot> [--yes]`

Writes the snapshot back and verifies by reading back. Refuses a snapshot for a different serial or an unsupported firmware. Without `--yes` on a terminal it asks first.

### `list-backups`

Lists the automatic backups for the device, newest first.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, including "already as desired" and "device absent" (the latter prints a warning to stderr) |
| 1 | Unexpected error (message names the operation and inputs) |
| 2 | Invalid desired state or arguments |
| 3 | No profile for this firmware, or the device is not an aquaero the tool understands |
| 4 | More than one device and no `--serial` |
| 5 | Permission denied (message says which access is missing) |
| 6 | Write rejected or read-back mismatch (message shows both values and the restore command) |
| 7 | Another instance holds the lock |
| 10 | Drift found, only with `apply --check --fail-on-drift` |

"Device absent" maps to 0 so a missing device never fails a system switch (FR-015); the warning is the only trace and the module surfaces it in the journal.

## Output guarantees

- Every `apply` prints, in order: the firmware and profile used, the backup path, the writes made, and the read-back result (SC-003).
- Errors name the failing operation and its inputs: device path, report id, byte offset (FR-017).
- No command writes without a saved backup. `dump`, `diff`, `show`, `plan`, `list-backups` and `apply --check` never write to the device.
