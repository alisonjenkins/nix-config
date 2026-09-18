# Nix deployment

Check for a repo-local wrapper first (`just`, `Makefile`, `bin/`, a `flake.nix`
app); many Nix configs alias the raw commands behind their own verbs. Prefer
it when present; it may carry repo-specific pre/post steps.

The build/test/boot/switch ladder (`nixos-rebuild` vs `darwin-rebuild` vs
`home-manager`, what reverts on reboot), the `git add`-before-build gotcha,
and the `nix flake check` cross-host caveat live in the `testing` skill's
`languages/nix.md`. This file only adds what is specific to *deploying*.

Remote machines: check what the repo uses (deploy-rs,
`nixos-rebuild --target-host`, colmena, morph, ...); don't assume one by
default.

## Rules

- Build before deploying: proves the closure evaluates and compiles without
  touching the target.
- Automatic rollback on failed activation (deploy-rs has it) covers only
  *activation* failures; a change that breaks *boot* will not roll back. For
  those, use a temporary `test`-style activation or a VM build first.
- Before assuming `sudo` is unavailable, **probe it**: `sudo -n true`, or
  `ssh -o BatchMode=yes <host> 'sudo -n true'`. Servers are often deliberately
  passwordless for remote operations; deferring to the user there wastes a
  round trip. Where the probe fails (typically an interactive workstation),
  hand the exact command to the user rather than retrying a password prompt
  that cannot succeed.
- systemd cannot infer ordering from a glob. A unit depending on
  wildcard-matched device or mount units races a slow dependency at boot.
  Generate an explicit barrier unit that expands the glob at build time.

## Authoring side

Module structure and conventions live in the `programming` skill's
`languages/nix.md`. A repo may carry its own workflow skill (host/module
scaffolding, secrets); check for one before assuming generic conventions
cover everything.
