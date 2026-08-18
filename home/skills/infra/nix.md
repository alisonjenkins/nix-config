# Nix deployment

Local machine, in increasing order of commitment:

```
just build [hostname]   # build only, no activation
just test               # activate temporarily; reverts on reboot
just boot               # set for next boot
just switch             # activate now, permanently
```

Remote machines go through deploy-rs:

```
just deploy [extraargs]
```

## Rules

- `git add` new files before building. Flakes ignore untracked files and the
  error does not say so.
- Build before deploying. `just build <hostname>` proves the closure evaluates
  and compiles without touching the target.
- deploy-rs has automatic rollback on a failed activation — but a change that
  breaks *boot* rather than activation will not roll back. For those, use
  `just test` locally or a VM build first.
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

Module structure, host scaffolding, secrets, and the haumea auto-discovery
rules live in the `programming` skill's `languages/nix.md` and, for this repo
specifically, the `nix-config-workflows` project skill.
