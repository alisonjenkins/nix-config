# Nix dev shell + packages

Run via `scripts/checks/dev-shell.sh <target>`. Local-repo-only — no forge API
involved.

## Criteria

- `flake.nix` present at repo root. If it is missing entirely, that is itself
  a finding, not a skip — Nix packaging is this house's standard way to build
  and develop software (no bare Dockerfiles, no assumed global toolchains; see
  `programming/languages/rust.md`'s "build with Nix" convention), so a repo
  without one is reported as needing it, regardless of what language it's in.
- `devShells.<system>.default` (or at least one named dev shell) exists, and
  provides the toolchain actually needed to build/test the repo.
- `packages.<system>.default` (or at least one named package) exists **in the
  same flake**, and `nix build .#<package>` succeeds — the flake is expected
  to serve both roles (dev shell and package build), not split across two
  mechanisms.
- `.envrc` present at repo root and wires up the flake's dev shell — `use
  flake`/`use nix`, or an equivalent hand-rolled `nix print-dev-env`/`nix
  develop` invocation (this repo's own `.envrc` skips the stock `use flake`
  gcroot-per-input behavior for cold-reload speed; that's a valid variant, not
  a finding), so `direnv` picks up the shell automatically on `cd`.
- Onboarding docs (`README.md` / `CONTRIBUTING.md`) mention `direnv allow` (or
  equivalent) so a new contributor knows the step exists.

## Forge

None of this needs a forge API — the check runs identically on GitHub,
GitLab, or no forge at all (a plain local clone).

## Fixing

`--fix` never invents a devShell/package definition from nothing — that
requires knowing the repo's actual toolchain, which is a judgment call, not a
mechanical fix. Instead it: scaffolds a `.envrc` with `use flake` when
`flake.nix` already exists but `.envrc` doesn't, and reports (without writing)
a starting-point `flake.nix` skeleton — matching one of this repo's own
`templates/<lang>/` scaffolds where the ecosystem matches — for the user to
review and commit themselves.
