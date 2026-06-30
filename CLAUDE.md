---
id: CLAUDE
aliases:
  - CLAUDE.md
tags: []
---
# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repo.

## Repository Overview

NixOS + nix-darwin flake. Manages many machines: desktops, laptops (Framework + work), servers (storage, K8s, VPN gateway, KVM hypervisor), macOS. home-manager for user-level config. Both NixOS + Darwin.

## Common Commands

### Building and Switching

Via `just` (justfile). Auto-uses `nh` if available, else `nixos-rebuild`/`darwin-rebuild`:

```bash
# Build and switch immediately
just switch [extraargs]
just s  # alias

# Build and set for next boot
just boot
just b  # alias

# Build without activating
just build [hostname] [extraargs]
just B  # alias

# Test temporarily (reverts on reboot)
just test [extraargs]
just t  # alias

# Update flake inputs
just update
just u  # alias

# Deploy to remote machines via deploy-rs
just deploy [extraargs]

# Build VM for testing
just test-build <hostname>

# Run built VM
just test-run <hostname>

# Build NixOS AMI image
just ami-build <hostname>

# Upload built AMI to AWS
just ami-upload <hostname> [region] [bucket]

# Build + upload AMI in one step
just ami <hostname> [region] [bucket]
```

### Common NixOS Operations

```bash
# Build specific host configuration
nix build ".#nixosConfigurations.<hostname>.config.system.build.toplevel"

# Check flake
nix flake check

# Show flake outputs
nix flake show

# Update specific input
nix flake lock --update-input <input-name>
```

## Architecture

**Dendritic Pattern**: flake-parts + haumea. Modular, auto-discovered.

### Directory Structure

- **`flake.nix`**: minimal entry (~50 lines outputs). Inputs + haumea auto-discovers flake-parts modules from `flake-modules/`.
- **`flake-modules/`**: all flake outputs, haumea auto-discovered:
  - `overlays.nix`: `flake.overlays` from `overlays/`
  - `deploy.nix`: deploy-rs nodes + checks
  - `dev-shells.nix`: `perSystem.devShells.default`
  - `templates.nix`: flake templates
  - `nixos-modules.nix`: `flake.nixosModules.*`
  - `home-modules.nix`: `flake.homeModules.*`
  - `hosts/`: one **dir** per host (NixOS/Darwin/standalone home-manager). Each: `default.nix` (flake-parts module), `hardware-configuration.nix` (→ `flake.nixosModules.<hostname>-hardware`), `disko-config.nix` (→ `flake.nixosModules.<hostname>-disko-config`)
- **`modules/`**: reusable NixOS modules, options pattern (`options.*` / `config = mkIf cfg.enable`):
  - `base/`: core (networking, boot, nix, impermanence, secure boot)
  - `desktop/`, `development/` (e.g. web dev), `locale/`
  - `libvirtd/`, `vr/`, `rocm/`, `llama-cpp/`, `servers/`: specialized
  - `desktop-base/`, `desktop-1password/`, `desktop-aws-tools/`, `desktop-kubernetes/`, etc.: desktop features
  - `desktop-greetd/`, `desktop-greetd-regreet/`, `desktop-sddm/`: display managers
  - `desktop-wm-plasma6/`, `desktop-wm-sway/`: WMs
  - `hardware-fingerprint/`, `hardware-touchpad/`: hardware features
  - `k8s-master/`, `storage-server/`: server roles
- **`home/`**: home-manager:
  - `home-linux.nix`, `home-macos.nix`, `home-common.nix`
  - `programs/`: per-program (zsh, neovim, tmux, git, ...)
  - `wms/`: WM configs (river, plasma, ...)
- **`pkgs/`**: custom packages/overrides
- **`overlays/`**: system-independent overlays (accept only `{ inputs }`, use `final.stdenv.hostPlatform.system`)
- **`secrets/`**: SOPS secrets (sops-nix, `.sops.yaml`)
- **`templates/`**: flake templates (e.g. Rust dev env)

### Configuration Pattern

Host = own flake-parts dir `flake-modules/hosts/<hostname>/`:
1. `default.nix`: defines `flake.nixosConfigurations.<hostname>` (or `darwinConfigurations`/`homeConfigurations`)
2. `hardware-configuration.nix`: → `flake.nixosModules.<hostname>-hardware`
3. `disko-config.nix`: → `flake.nixosModules.<hostname>-disko-config`

Custom modules via `self.nixosModules.*` (exported in `nixos-modules.nix`), enabled `modules.<name>.enable = true`. Home modules via `self.homeModules.*`. Secret/patch paths via `self + "/path"`. No relative imports (`../../`) — all via flake outputs. New `flake-modules/` files auto-discovered by haumea.

`modules/base` options under `modules.base`:
- `enable`; `bootLoader` (enum `"systemd-boot"` / `"grub"` / `"secure-boot"` = Lanzaboote+TPM); `pcr15Value` (TPM PCR15 for LUKS, required when secure-boot)
- `enableImpermanence`, `impermanencePersistencePath` (default `/persistence`)
- `enableCachyOSKernel`
- `enableOpenSSH`, `enableTailscale`, `enableIPv6`, `enableICMPPing`
- `suspendState` (`"mem"` / `"standby"` / `"freeze"` / `null`), `hibernateMode` (`"platform"` / `"shutdown"`)
- `timezone`, `consoleKeyMap`
- `beesdFilesystems` (btrfs dedup)

### Key Systems

**Overlays** (system-independent, channel access): `pkgs.stable` (nixpkgs 25.11), `pkgs.unstable` (nixos-unstable), `pkgs.master` (master). In `overlays/default.nix`, exported `flake-modules/overlays.nix`, applied per-host.

**Impermanence**: some hosts tmpfs root + selective persistence; per-host paths.

**Secrets**: sops-nix + age. Keys + path rules in `.sops.yaml`.

**Remote Deploy**: `deploy` attr via deploy-rs, in `flake-modules/deploy.nix`.

### Active Hosts

- **Desktop/Laptop**: `ali-desktop`, `ali-framework-laptop`, `ali-work-laptop`, `ali-mba-linux` (M1 MacBook Air, NixOS-on-Asahi, aarch64-linux)
- **macOS**: `Alisons-MacBook-Pro` (Darwin, work)
- **Servers**: `home-storage-server-1`, `home-kvm-hypervisor-1`, `home-k8s-master-1`, `home-k8s-server-1`, `home-vpn-gateway-1`, `download-server-1`
- **Dev/Test**: `dev-vm` (aarch64-linux VM)
- **Home-Manager Only**: `ali` (Arch Linux), `deck` (Steam Deck)

### Notable Flake Inputs

`ali-neovim` (custom neovim flake), `home-manager`, `stylix` (theming), `plasma-manager`, `sops-nix`, `disko`, `lanzaboote` (Secure Boot), `impermanence`, `deploy-rs`, `nixos-hardware` (e.g. Framework 16), `nixos-cosmic`, `rust-overlay`, `jovian-nixos` (Steam Deck), `niks3` (self-hosted binary cache push).

### CI/CD Workflows

- **`build-and-cache.yaml`**: builds all nixosConfigurations on push to main → niks3 cache. Dry-run skips cached; parallel build+push via queue drain.
- **`update.yaml`**: daily flake lock update (2 AM UTC)
- **`ami-build-and-upload.yaml`**: builds+uploads NixOS AMIs to AWS, retention cleanup
- **`closure-report.yaml`**: closure size reports for desktop/laptop configs

### Minecraft modpack server packaging

Lives in the **`minecraft-modpack-packaging`** skill (`.claude/skills/minecraft-modpack-packaging/SKILL.md`) — `create-sky-colonies-server` (vanilla) + `create-arkana-aeronautics-server` (manifest+bisection) patterns, the bisect loop, mod-version bumping (`find-mod-bumps`), composition files, crash triage. Auto-loads when working on `pkgs/create-*-server` / `pkgs/minecraft-modpack-tools`.

### Dev workflows + pending work

- **How to** modify configs / add hosts / modules / flake-modules / secrets → the **`nix-config-workflows`** skill (`.claude/skills/nix-config-workflows/SKILL.md`), auto-loads for that work.
- **Pending / unfinished** work (niks3 cache-push enablement, emulation module follow-ups) → `PENDING.md` (repo root).
