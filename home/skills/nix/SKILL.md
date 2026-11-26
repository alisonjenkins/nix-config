---
name: nix
description: >-
  Use for Nix repo workflows beyond writing Nix code: bumping, adding,
  removing, pinning or deduplicating inputs, or choosing between flake.lock
  and tack (.tack/pins.toml): nix flake update, nix flake lock,
  --override-input, follows, tack update/add/look/dedup, tack init --convert,
  patched or frozen pins. Detects which input system a repo uses, including
  both at once. Not for writing Nix modules (programming), deploying a host
  (infra) or auditing a closure (security).
---

# Nix

Workflows on a Nix repo that are not writing Nix: today, managing its
inputs. Each child file holds one workflow.

## General rules

- **Read the repo's own instructions first.** `AGENTS.md` or a repo skill
  may name a wrapper (`just update`, an update bot) or a policy that wraps
  the raw commands below. The repo's rule wins.
- **Run tools through Nix, not `PATH`.** `nix shell nixpkgs#tack -c tack ...`
  or the repo's dev shell. Do not assume a tool is installed.
- **Never change the input system as a side effect.** A bump stays in the
  repo's current system; switching is a separate decision for the user.

## Routing

| Doing | Read |
|---|---|
| Bumping, adding, removing, pinning or deduplicating inputs; flake.lock or tack; whether to adopt tack | [inputs.md](inputs.md) |

## Nix work owned elsewhere

| Doing | Skill |
|---|---|
| Writing or fixing `.nix` code, modules, overlays, eval errors | `programming` (`languages/nix.md`) |
| `nix flake check`, NixOS VM tests | `testing` (`languages/nix.md`) |
| `nixos-rebuild`, `home-manager switch`, deploy-rs | `infra` |
| Closure audit, CVEs in a closure | `security` (`nix-closure.md`) |
