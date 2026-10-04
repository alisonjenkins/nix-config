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
- `check-restored-pvcs.sh`: run after a Velero restore into a scratch namespace and before any restored pod runs; fails if a restored PVC names a volume that belongs to another claim (it would let the restore write into that volume).
- `check-world.sh WORLD_DIR`: proves a Minecraft world's region files are readable. Decodes every chunk of every `.mca`
  under every `region` directory (overworld, `DIM-1`, `DIM1`, `dimensions/<ns>/<name>`; `entities` and `poi` are
  ignored) to a valid NBT root, prints one `unreadable` line per bad chunk and a final `chunks_read= unreadable= files=`
  line. Exit 0 only when nothing is unreadable and at least one chunk was read; 2 on a usage error. Read-only; uses
  one worker per CPU (`CHECK_WORLD_JOBS` overrides). The LZ4 block checksum is not verified. `check-world.py` is its
  implementation.
- `staging-pod.yaml`: a read-only pod that mounts one claim so Velero can back up a volume whose workload is scaled to zero (Grafana, the Minecraft world). Usage and the restore caveat are in its header.
- `tests/`: bats tests, with fixture-driven fakes for `kubectl`, `lsblk`, `cryptsetup`, `curl`, `hcloud` and a node
  shell in `tests/bin`. `tests/sql.bats` runs the checksum query against a real throwaway Postgres.
  `tests/make-region.py` writes the Anvil fixture worlds for `tests/check-world.bats`.

- `migrate-files.sh`: copies a files volume onto its replacement. Refuses unless the Deployment or StatefulSet is at
  zero replicas, no pod mounts either claim and the copy job does not already exist. Runs `copy-job.yaml` (`rsync -a
  --checksum`, old claim read-only), waits for it, refuses with the failing step named if it failed, and saves
  `old.manifest` and `new.manifest` (path, bytes, sha256, uid:gid) in `--manifest-dir` for `verify.sh --kind files
  --old-manifest ... --new-manifest ...`. A dry run unless `--execute` is given. The job image comes from
  `COPY_IMAGE`. The job runs non-root (Pod Security `restricted`) as `--uid`/`--gid`, which must equal the owner of
  the files on the old claim, or `rsync -a` cannot keep ownership and the owner column of the manifests differs. The finished Job stays as a record, delete it before copying again.
- `copy-job.yaml`: the Job that `migrate-files.sh` renders with `envsubst`.

## Rules

- Never print a secret, a passphrase or a token. Errors name the failing operation and its inputs.
- Times are ISO 8601 UTC.
- A script that can change a live system takes an explicit flag and is only run with the owner's consent.
