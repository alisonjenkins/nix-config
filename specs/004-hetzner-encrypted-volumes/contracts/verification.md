# Contract: migration verification

Every volume migration passes this gate before its old volume may be destroyed (spec FR-006,
FR-007). It has four parts. All must pass. A failure leaves the old volume intact and in use,
or switchable back to, and the new volume is removed.

The gate is run by a script and its output is the record (FR-011). Times are ISO 8601 UTC.

## 0. Encryption is real

A volume that mounted is not proof that it is encrypted. The storage driver encrypts only if
the passphrase Secret is present and non-empty, and it may mount plain text otherwise. This
check runs first.

| Check | Pass condition |
|---|---|
| Device-mapper crypt mapping | On the node, the volume's device is under a `crypt` mapping (`lsblk -f` shows `crypto_LUKS`, `cryptsetup status` reports an active mapping) |
| Raw device unreadable | Reading the raw block device does not show the filesystem's magic bytes or known file content |
| Passphrase Secret | The Secret exists, is non-empty, and is the one the StorageClass references |

## 1. Data comparison

Compared against a snapshot taken at the moment of the switch, not at the start of the copy.

| Volume kind | Inputs | Pass condition |
|---|---|---|
| Database | row counts per table, and a checksum per table, per database | identical on the old and new instance |
| Files | file count, total bytes, and a checksum per file | identical paths, sizes and checksums |

Databases are compared while writes are paused, or against a replica that has reported zero lag
and is read at a known position.

## 2. Service health

| Check | Pass condition |
|---|---|
| Pod state | the workload's pods are Ready, with no restarts since the switch |
| Own health endpoint | returns success for 5 consecutive minutes |
| Logs | no errors about the volume, permissions or database connection |

## 3. Functional check

| Service | Check |
|---|---|
| Matrix (database and media) | using the dedicated test account `verify-bot` (never a household account): send a message in its private test room and read it back; sign in; upload a file and download it; open a known older piece of media |
| Photo service database | using a dedicated test account: sign in and list a test album |
| Document database | read a known document and write a test document |
| Monitoring | Prometheus answers a query that spans the migration; Alertmanager lists its silences; Grafana loads its data sources |
| Notification server | publish and receive a test notification |
| Game server | start it, join once, then scale it back to zero. For a restored or migrated world, also run `check-world.sh`: read every chunk of every region file, with zero unreadable chunks |

## 4. Fresh backup

A backup of the new volume's data is taken and listed as completed. For a database this is a
base backup plus archived changes. For other volumes it is a Velero backup. The backup must
exist before the old volume is destroyed.

## Output

The script prints one line per check, then a final verdict:

```text
2026-10-03T14:02:11Z volume=matrix-stack-synapse-media check=encryption result=pass detail="crypto_LUKS on /dev/mapper/pvc-..."
2026-10-03T14:02:40Z volume=matrix-stack-synapse-media check=compare result=pass detail="files=18342 bytes=859832110"
...
2026-10-03T14:09:55Z volume=matrix-stack-synapse-media verdict=verified
```

Any failing line ends with `verdict=failed` and names the failing check. The script exits
non-zero. Errors carry the failing operation and its inputs (constitution IV).
