# Testing Nix

## Levels
- **Evaluation**: `nix flake check` catches eval errors and runs the deploy-rs
  checks. Note that a broken input for one platform (for example a Darwin or
  Asahi-only derivation) can fail the whole check from the wrong host —
  `--skip-checks` is legitimate there, but say so rather than hiding it.
- **Build**: `just build <hostname>` builds a host's toplevel without
  activating. This is the cheapest real proof that a module change is sound.
- **Activation**: `just test` activates temporarily and reverts on reboot —
  the safe way to try a change that could break boot or display.
- **VM**: `just test-build <hostname>` then `just test-run <hostname>` for a
  full boot in a VM, which is the only way to test boot-path and disk changes
  without risking the machine.

## Practice
- `git add` new files before any of the above; flakes ignore untracked files
  and the error message does not say so.
- Assert on the built result, not on the fact that evaluation succeeded — for
  example, list the produced directory when the change is about file layout.
- NixOS VM tests (`pkgs.testers.runNixOSTest`) for service modules whose
  behaviour is a systemd unit coming up and answering.
