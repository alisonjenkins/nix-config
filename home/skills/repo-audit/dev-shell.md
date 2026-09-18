# Nix dev shell + packages

Run via `scripts/checks/dev-shell.sh <target>`. Local-repo-only, no forge API
involved.

## Criteria

- `flake.nix` present at repo root. Nix dev environments are a personal
  convention (no bare Dockerfiles, no assumed global toolchains, see
  `programming/languages/rust.md`'s "build with Nix"), **not a universal
  standard**, so a missing `flake.nix` is a skip (suggestion, not failure) to
  avoid noise on repos, teams, or workplaces without Nix. The remaining
  criteria only evaluate once `flake.nix` exists.
- `devShells.<system>.default` (or at least one named dev shell) exists and
  provides the toolchain needed to build/test the repo.
- `packages.<system>.default` (or at least one named package) exists **in the
  same flake**, and `nix build .#<package>` succeeds; one flake serves both
  roles, not split across two mechanisms.
- `.envrc` at repo root wires up the flake's dev shell via
  `use flake`/`use nix`, or a hand-rolled `nix print-dev-env`/`nix develop`
  invocation (a repo may skip stock `use flake`'s gcroot-per-input behavior
  for cold-reload speed; valid variant, not a finding), so `direnv` picks up
  the shell on `cd`.
- Onboarding docs (`README.md` / `CONTRIBUTING.md`) mention `direnv allow` (or
  equivalent) so a new contributor knows the step exists.

## Forge

No forge API needed; runs identically on GitHub, GitLab, or a plain local
clone.

## Fixing

`--fix` never invents a devShell/package/flake.nix from nothing: that needs
the repo's actual toolchain, a judgment call. It only scaffolds a `.envrc`
with `use flake`, and only when `flake.nix` exists but `.envrc` doesn't. A
missing `flake.nix` stays a skip/suggestion (see Criteria) for the user to
write themselves.
