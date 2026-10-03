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

Nothing yet. The scripts arrive with their tests in the order of `specs/004-hetzner-encrypted-volumes/tasks.md`:
`verify.sh`, `retain-pv.sh`, `destroy-old-volume.sh`, `check-no-call.sh`, `migrate-files.sh` and `check-world.sh`.

## Rules

- Never print a secret, a passphrase or a token. Errors name the failing operation and its inputs.
- Times are ISO 8601 UTC.
- A script that can change a live system takes an explicit flag and is only run with the owner's consent.
