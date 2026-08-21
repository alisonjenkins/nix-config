# Nix deployment

Check for a repo-local wrapper first (`just`, `Makefile`, `bin/`, a `flake.nix`
app) — many Nix configs alias the raw commands below behind their own verbs.
If one exists, prefer it; it may carry repo-specific pre/post steps. Otherwise
use the underlying tools directly, in increasing order of commitment:

```
nixos-rebuild build --flake .#<host>     # build only, no activation
nixos-rebuild test --flake .#<host>      # activate temporarily; reverts on reboot
nixos-rebuild boot --flake .#<host>      # set for next boot
nixos-rebuild switch --flake .#<host>    # activate now, permanently
```

nix-darwin and standalone home-manager don't have the full verb set above —
neither has a bootloader-staged `boot`, and neither has a reboot-reverting
`test`:
- nix-darwin: `darwin-rebuild build --flake .#<host>` /
  `darwin-rebuild switch --flake .#<host>` (switch activates immediately,
  permanently — there is no temporary/reverting mode).
- standalone home-manager: `home-manager build --flake .#<user>@<host>` /
  `home-manager switch --flake .#<user>@<host>` — note the flake target is
  `<user>@<host>`, not `<host>`.

Remote machines: check what the repo uses for remote deploy (deploy-rs,
`nixos-rebuild --target-host`, colmena, morph, ...) — don't assume any one of
these by default.

## Rules

- `git add` new files before building. Flakes ignore untracked files and the
  error does not say so.
- Build before deploying — prove the closure evaluates and compiles without
  touching the target first.
- If the deploy tool has automatic rollback on failed activation (deploy-rs
  does), remember it only covers *activation* failures — a change that breaks
  *boot* will not roll back. For those, use a temporary `test`-style
  activation or a VM build first.
- `nix flake check` may fail from the wrong host when an input only evaluates
  on another platform. Skipping it is legitimate; say that you skipped it.
- Before assuming `sudo` is unavailable, **probe it**: `sudo -n true`, or
  `ssh -o BatchMode=yes <host> 'sudo -n true'`. Servers are often deliberately
  configured passwordless for remote operations, and deferring to the user on
  those wastes a round trip. Where the probe fails — typically an interactive
  workstation — hand the exact command to the user rather than retrying a
  password prompt that cannot succeed.
- systemd cannot infer ordering from a glob. A unit that depends on
  wildcard-matched device or mount units will race a slow dependency at boot.
  Generate an explicit barrier unit that expands the glob at build time.

## Authoring side

General module structure and conventions live in the `programming` skill's
`languages/nix.md`. A given repo may carry its own project-local workflow
skill (host/module scaffolding, secrets) — check for one before assuming
generic conventions cover everything.
