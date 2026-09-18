# Nix deployment

Check for a repo-local wrapper first (`just`, `Makefile`, `bin/`, a `flake.nix`
app); many Nix configs alias the raw commands below behind their own verbs.
If one exists, prefer it; it may carry repo-specific pre/post steps.

For the build/test/boot/switch command ladder (`nixos-rebuild` vs
`darwin-rebuild` vs `home-manager`, what reverts on reboot and what doesn't),
the `git add`-before-build gotcha, and the `nix flake check` cross-host
caveat, see the `testing` skill's `languages/nix.md` — this file only adds
what's specific to *deploying*, below.

Remote machines: check what the repo uses for remote deploy (deploy-rs,
`nixos-rebuild --target-host`, colmena, morph, ...); don't assume any one of
these by default.

## Rules

- Build before deploying, to prove the closure evaluates and compiles without
  touching the target first.
- If the deploy tool has automatic rollback on failed activation (deploy-rs
  does), remember it only covers *activation* failures; a change that breaks
  *boot* will not roll back. For those, use a temporary `test`-style
  activation or a VM build first.
- Before assuming `sudo` is unavailable, **probe it**: `sudo -n true`, or
  `ssh -o BatchMode=yes <host> 'sudo -n true'`. Servers are often deliberately
  configured passwordless for remote operations, and deferring to the user on
  those wastes a round trip. Where the probe fails, typically an interactive
  workstation, hand the exact command to the user rather than retrying a
  password prompt that cannot succeed.
- systemd cannot infer ordering from a glob. A unit that depends on
  wildcard-matched device or mount units will race a slow dependency at boot.
  Generate an explicit barrier unit that expands the glob at build time.

## Authoring side

General module structure and conventions live in the `programming` skill's
`languages/nix.md`. A given repo may carry its own project-local workflow
skill (host/module scaffolding, secrets); check for one before assuming
generic conventions cover everything.
