---
name: build
description: Build NixOS/darwin/home configs from this flake without activating.
  Use when user runs /build, says "build <host>", "build the servers", or
  "check the config builds".
argument-hint: "[host|group ...]"
---

# /build — build configs, never activate

## Resolve targets

- No args → current host: run `hostname`.
- Args → hosts and/or groups. Expand groups, dedupe, keep order.
- Unknown name → list valid hosts/groups, stop.

## Groups

- `servers`: download-server-1 home-kvm-hypervisor-1 home-storage-server-1 home-k8s-master-1
- `laptops`: ali-framework-laptop ali-work-laptop ali-mba-linux
- `all`: servers + laptops + ali-desktop + ali-steam-deck (= all 9 deploy-rs nodes)

## Host registry

| host | attr set | arch | deploy node |
|---|---|---|---|
| ali-desktop | nixosConfigurations | x86_64-linux | yes (root@100.127.142.30 — this machine) |
| ali-framework-laptop | nixosConfigurations | x86_64-linux | yes |
| ali-steam-deck | nixosConfigurations | x86_64-linux | yes |
| ali-work-laptop | nixosConfigurations | x86_64-linux | yes |
| ali-mba-linux | nixosConfigurations | aarch64-linux | yes |
| download-server-1 | nixosConfigurations | x86_64-linux | yes |
| home-kvm-hypervisor-1 | nixosConfigurations | x86_64-linux | yes |
| home-storage-server-1 | nixosConfigurations | x86_64-linux | yes |
| home-k8s-master-1 | nixosConfigurations | x86_64-linux | yes |
| home-k8s-server-1 | nixosConfigurations | x86_64-linux | no (node commented out) |
| dev-vm | nixosConfigurations | aarch64-linux | no |
| home-vpn-gateway-1 | nixosConfigurations | x86_64-linux | no |
| home-vpn-gateway-1-vm | nixosConfigurations | x86_64-linux | no |
| installer-iso | nixosConfigurations | x86_64-linux | no |
| ali-mba | darwinConfigurations | aarch64-darwin | no |
| Alisons-MacBook-Pro | darwinConfigurations | aarch64-darwin | no |
| ali | homeConfigurations | x86_64-linux | no |
| deck | homeConfigurations | x86_64-linux | no |

Ground truth for deploy nodes is `flake-modules/deploy.nix` — trust it over this table.

Arch rules:
- darwin hosts: buildable only on a darwin machine. On Linux: refuse with that reason.
- aarch64-linux hosts: build fine on ali-desktop via qemu binfmt — expect 2-5x slower; say so up front.

## Build commands (sequential, one host at a time)

Shared closure means later hosts mostly cache-hit; sequential keeps error attribution clean.

- NixOS host: `just build <host>` (nh path, performance power profile, no sudo)
- darwin (darwin machine only): `nix build .#darwinConfigurations.<name>.system`
- home config: `nix build .#homeConfigurations.<name>.activationPackage`

Long builds (10-60 min): run via Bash with `run_in_background: true`. Poll output every
few minutes; post a one-line progress note when something meaningful changes. Never
foreground-block. Do useful prep (e.g. pre-read the next host's config) while waiting.

## On failure: debug loop

1. Capture the real error. Eval error → rerun `just build <host> --show-trace`.
   Derivation failure → `nix log <failing .drv>`.
2. Classify:
   - **untracked file**: flake eval only sees git-tracked files. "path ... does not
     exist" but file exists on disk → `git add <file>` (add OK, commit NOT OK). Most
     common failure here after creating new files.
   - **eval/type/option error** → fix the nix code, minimal diff.
   - **stale fetcher hash** → replace with the "got:" hash from the error.
   - **upstream derivation failure** → try patch/override/version pin; if hopeless,
     mark FAILED.
3. Rebuild ONLY the failed host. Max 5 fix iterations per host, then FAILED, move on.

Hard rules: never `git commit`/`git push`. Never sudo. Never activate.

## Final report

| host | result | time | notes |

Then **Fixes made**: file → one-line what/why each. Remind user fixes are uncommitted —
review and commit yourself.

To activate the current host: user runs `just boot`/`just test`/`just switch` themselves
(needs sudo) — or `/deploy ali-desktop` (root-over-ssh, no local sudo needed).
