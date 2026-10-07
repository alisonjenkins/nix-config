# 0029. Run the PR check's sections in parallel, one eval per output set

- Status: Accepted
- Date: 2026-10-07

## Context

The `flake-check` job in `PR check` took 6–11 min per run. Everything was in
`.github/scripts/pr-check-x86_64-linux.sh`, which ran its sections back to
back. From run 37582621479:

| Section | Time |
|---|---|
| modules, overlays, devShells | 26s |
| packages eval | 88s |
| three bats builds | ~120s |
| aarch64 host evals | 108s |

Packages and hosts were evaluated one `nix eval` process per entry, so each
paid startup and re-evaluated shared nixpkgs.

## Decision

- Each output set is evaluated in one `nix eval`. Only if that fails does the
  script fall back to one eval per entry, so a failure still names the broken
  one.
- The sections run concurrently as background subshells. Each logs to its own
  file, printed whole as soon as that section finishes.

Result: ~47s locally, 1m45s in CI.

## Things that are not obvious

- **Evals count against the runner pod's memory.** `nix eval` runs in the
  client, inside the runner pod (16Gi limit in home-cluster's
  `home-nix-builder-amd64` HelmRelease). Builds run in the host daemon and
  escape it. All sections together peaked at ~8GiB of `nix*` RSS, an
  overestimate because it includes the daemon. Re-check against the limit
  before adding concurrent evals.
- **Cancelling must signal process groups.** `cancel-in-progress` sends TERM
  to the script. `kill $(jobs -p)` only reached the section subshells, and the
  `nix` clients under them kept running into the next run. `set -m` gives each
  section its own group, and the trap kills `-<pid>`. The bats test for this
  fails with the old kill.
- **Output is printed per section, not at the end.** A hung section otherwise
  hides every other section's log when the 30-minute timeout kills the job.
- **A section that dies before reporting is FAILED.** Its `N.rc` marker never
  appears (disk full, killed), and waiting for it would burn the whole timeout.

## Known gap

`build_changed_packages` runs `git fetch --depth=1 origin main`. In CI that is
harmless (the checkout is already shallow). In a local checkout, `just check`
makes the repo shallow, which breaks `merge-base` and makes the next rebase
conflict on commits that are not yours. `git fetch --unshallow` repairs it.
Not fixed here.

## Alternatives rejected

- **Split sections into separate GitHub jobs.** Each pays checkout and Nix
  setup, and `flake-check` is the required status check on `main`, so the
  job structure would have to be reworked with it.
- **Cut host coverage.** The aarch64 evals exist because a lock bump once
  broke hosts nothing else evaluates.
