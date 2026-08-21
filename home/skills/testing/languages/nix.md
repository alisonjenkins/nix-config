# Testing Nix

## Levels
- **Evaluation**: `nix flake check` catches eval errors and runs any flake
  checks (deploy-rs checks, custom checks, etc). Note that a broken input for
  one platform (e.g. a Darwin-only or otherwise platform-gated derivation) can
  fail the whole check from the wrong host — skipping it (`--skip-checks` if
  the repo wraps this, or excluding the failing check) is legitimate there,
  but say so rather than hiding it.
- **Build**: build a host's/target's toplevel without activating (raw
  `nixos-rebuild build --flake .#<host>`, or the repo's own wrapper if one
  exists — check `infra/nix.md`). This is the cheapest real proof that a
  module change is sound.
- **Activation**: a temporary activation (`nixos-rebuild test`/`darwin-rebuild
  test` or repo wrapper) that reverts on reboot — the safe way to try a
  change that could break boot or display.
- **VM**: `nixos-rebuild build-vm --flake .#<host>` (the `--flake .#<host>`
  matters — omitting it silently builds the wrong/default configuration in a
  flake-based repo), or a `nixosTest`/VM-build wrapper the repo provides, for
  a full boot in a VM — the only way to test boot-path and disk changes
  without risking the machine.

## Practice
- `git add` new files before any of the above; flakes ignore untracked files
  and the error message does not say so.
- Assert on the built result, not on the fact that evaluation succeeded — for
  example, list the produced directory when the change is about file layout.
- NixOS VM tests (`pkgs.testers.runNixOSTest`) for service modules whose
  behaviour is a systemd unit coming up and answering.
