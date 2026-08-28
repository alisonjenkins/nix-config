# Nix dev shell + packages

Run via `scripts/checks/dev-shell.sh <target>`. Local-repo-only, no forge API
involved.

## Criteria

- `flake.nix` present at repo root. Nix-based dev environments are a personal
  convention (no bare Dockerfiles, no assumed global toolchains, see
  `programming/languages/rust.md`'s "build with Nix" convention), **not a
  universal standard**, so a missing `flake.nix` is reported as a skip
  (suggestion, not a failure) so this doesn't manufacture noise on repos,
  teams, or workplaces that haven't adopted Nix. The rest of this criterion
  only evaluates once a `flake.nix` already exists.
- `devShells.<system>.default` (or at least one named dev shell) exists, and
  provides the toolchain actually needed to build/test the repo.
- `packages.<system>.default` (or at least one named package) exists **in the
  same flake**, and `nix build .#<package>` succeeds; the flake is expected
  to serve both roles (dev shell and package build), not split across two
  mechanisms.
- `.envrc` present at repo root and wires up the flake's dev shell, via
  `use flake`/`use nix`, or an equivalent hand-rolled
  `nix print-dev-env`/`nix develop` invocation (a repo may skip the stock
  `use flake` gcroot-per-input behavior for cold-reload speed; that's a valid
  variant, not a finding), so
  `direnv` picks up the shell automatically on `cd`.
- Onboarding docs (`README.md` / `CONTRIBUTING.md`) mention `direnv allow` (or
  equivalent) so a new contributor knows the step exists.

## Forge

None of this needs a forge API; the check runs identically on GitHub,
GitLab, or no forge at all (a plain local clone).

## Fixing

`--fix` never invents a devShell/package/flake.nix definition from nothing,
because that requires knowing the repo's actual toolchain, which is a
judgment call, not a mechanical fix. It only scaffolds a `.envrc` with
`use flake`, and only when `flake.nix` already exists but `.envrc` doesn't:
a missing `flake.nix` itself is left as a skip/suggestion (see Criteria
above) for the user to write and commit themselves.
