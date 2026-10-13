# Data Model: Aquaero Fan Controller Configuration on Linux

**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

Field names and types only. Anything marked *unknown* is settled by the discovery work, not here.

## Device

| Field | Type | Notes |
|-------|------|-------|
| `hidraw_path` | path | The node that passed the report 0x0B check (research R2) |
| `serial` | string | Read from the configuration (kernel driver reads it at offset 0x07) |
| `firmware` | integer | Read at offset 0x0B per the driver; *unknown* if this is also what the profile keys on |

Identity: vendor `0x0c70`, product `0xf001`, plus `serial`. With more than one device the owner MUST pass the serial (FR-018).

## ConfigSnapshot

The unit of backup, comparison and restore.

| Field | Type | Rules |
|-------|------|-------|
| `bytes` | byte array | Exactly 0xa93 (2707) bytes; a different length is rejected |
| `meta.serial` | string | |
| `meta.firmware` | integer | |
| `meta.taken_at` | string | ISO 8601 UTC, e.g. `2026-10-13T09:50:12Z` |
| `meta.label` | string | Free text, `[a-z0-9-]` after normalisation |
| `meta.sha256` | string | Hash of `bytes`; verified on load |
| `meta.tool_version` | string | |

Stored as `<taken_at>-<label>.bin` (raw bytes) and `<same>.json` (the `meta` fields). A load fails if the length or hash does not match.

## ByteDiff

The result of comparing two snapshots.

| Field | Type | Notes |
|-------|------|-------|
| `offset` | integer | Position in the 0xa93 bytes |
| `before` / `after` | byte | |
| `volatile` | boolean | True when the position also differed between two untouched snapshots |

Contiguous differing bytes are grouped into runs for display. Volatile positions are excluded from "what a setting changed".

## FirmwareProfile

Keyed by firmware version; embedded in the binary; added only once the layout is verified.

| Field | Type | Notes |
|-------|------|-------|
| `firmware` | integer | Version this profile is verified for |
| `verified_on` | list | Dates and serial-redacted device notes |
| `fan[n].min_percent` | field | Position, width, encoding, range |
| `fan[n].source_sensor` | field | Which temperature drives the fan |
| `fan[n].curve` | field group | *Unknown*: point count, resolution, positions |
| `fan[n].sensor_loss_behaviour` | field | *Unknown*: where and how the fallback speed is stored |
| `commit` | sequence | *Unknown*: the report sequence that makes the device keep the change |

A device whose firmware has no profile is not writable (FR-006).

## FanCurve

| Field | Type | Rules |
|-------|------|-------|
| `fan` | 1 to 4 | v1 supports 4 only; others are left untouched |
| `sensor` | 1 to 8 | v1 supports 1 only (coolant) |
| `min_percent` | 0 to 100 | Floor; the fans never go below it |
| `points` | list of (temperature °C, percent) | At least 2; temperature strictly increasing; percent non-decreasing and at or above `min_percent`; within the point count the profile allows |
| `on_sensor_loss` | percent | Fixed at 100 (FR-011) |

Validation failures name the offending value and are raised before any device access (FR-016).

## DesiredState

What the NixOS module renders to JSON in the store.

| Field | Type | Notes |
|-------|------|-------|
| `device_serial` | string or null | Null means "the only aquaero present" |
| `mode` | `apply` or `check` | Per the clarification: `check` never writes |
| `fans` | map of fan number to `FanCurve` | |

## Plan

Computed from a `DesiredState`, a `ConfigSnapshot` and a `FirmwareProfile`.

| Field | Type | Notes |
|-------|------|-------|
| `changes` | list | Each: setting name, old value, new value, byte positions touched |
| `untouched_equal` | boolean | True when every byte outside `changes` is preserved (FR-005, SC-007) |
| `already_applied` | boolean | True when `changes` is empty; no write happens (SC-004) |

## Backup

A `ConfigSnapshot` taken automatically before a write, stored under the backup directory for the device. Restore takes a backup (or any snapshot) and writes it back.

## State transitions: one apply

```text
read snapshot -> check firmware has profile -> validate desired state
  -> compute plan -> (already applied? stop)
  -> save backup -> write -> read back -> compare with intended
  -> ok: report | mismatch or error: report last known state and the restore command
```

A restore follows the same path with the chosen snapshot as the intended bytes. A failure at any step after the backup leaves the owner a one-command route back.
