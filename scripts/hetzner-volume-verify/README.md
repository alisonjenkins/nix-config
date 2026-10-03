# hetzner-volume-verify

Checks for moving the Hetzner cluster's data volumes to encrypted storage. The rules they enforce are
in [`specs/004-hetzner-encrypted-volumes/contracts/verification.md`](../../specs/004-hetzner-encrypted-volumes/contracts/verification.md).
The reasons are in [ADR 0022](../../docs/adr/0022-encrypt-hetzner-volumes.md).

## Use

Every tool comes from this directory's dev shell, never from `PATH`:

```sh
cd scripts/hetzner-volume-verify
nix develop
export KUBECONFIG=~/.kube/hetzner-cp.yaml
bats tests
```

Scripts are written test first: a failing `bats` test in `tests/`, then the script that passes it.

## Contents

- `verify.sh`: the verification gate, one result line per check and a final `verdict=`. Run it with no arguments
  for its options. `--checks` is required. Run the encryption check with `--node-exec` set to a command that runs on
  the node holding the volume. The Matrix functional check reads `VERIFY_BOT_TOKEN` (an access token for
  `verify-bot`, because Synapse here does not serve password login) and `VERIFY_BOT_ROOM` from the environment. The
  functional checks for photos, documents, notifications and the game server are not implemented yet: they fail
  closed, so the gate never passes without them being run by hand and recorded.
- `table-checksums.sql`: the per-table row count and checksum that the database comparison runs through `psql`.
- `retain-pv.sh`: sets a PersistentVolume to `Retain`.
- `destroy-old-volume.sh`: removes an old volume, only after a verified verdict newer than the switch, a completed
  backup of the same target, and a `Retain` PV, with no pod mounting the claim. A dry run unless `--execute` is given.
- `check-no-call.sh`: prints `calls=N` from every SFU pod and exits 0 only at zero. It fails closed.
- `tests/`: bats tests, with fixture-driven fakes for `kubectl`, `lsblk`, `cryptsetup`, `curl`, `hcloud` and a node
  shell in `tests/bin`. `tests/sql.bats` runs the checksum query against a real throwaway Postgres.

Still to come, in the order of `specs/004-hetzner-encrypted-volumes/tasks.md`: `migrate-files.sh` and `check-world.sh`.

## Rules

- Never print a secret, a passphrase or a token. Errors name the failing operation and its inputs.
- Times are ISO 8601 UTC.
- A script that can change a live system takes an explicit flag and is only run with the owner's consent.
