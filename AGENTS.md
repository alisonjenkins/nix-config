# AGENTS.md

## Repository Overview

NixOS and nix-darwin flake configuration managing multiple machines including desktops, laptops (Framework and work), servers (storage, K8s, VPN gateway, KVM hypervisor), and macOS systems. Uses home-manager for user-level configuration and supports both NixOS and Darwin systems.

## Build Commands

### Primary Commands (via `just`)
All commands use `just` (justfile) with automatic fallback from `nh` to `nixos-rebuild`/`darwin-rebuild`:

```bash
# Build and switch immediately
just switch [extraargs]  # alias: just s

# Build and set for next boot
just boot  # alias: just b

# Build without activating
just build [hostname] [extraargs]  # alias: just B

# Test temporarily (reverts on reboot)
just test [extraargs]  # alias: just t

# Update flake inputs
just update  # alias: just u

# Deploy to remote machines via deploy-rs
just deploy [extraargs]

# VM testing
just test-build <hostname>  # Build VM
just test-run <hostname>    # Run built VM

# Build NixOS AMI image
just ami-build <hostname>

# Upload built AMI to AWS
just ami-upload <hostname> [region] [bucket]

# Build + upload AMI in one step
just ami <hostname> [region] [bucket]
```

### Commit hooks

`prek install --allow-missing-config` once per clone (prek is in the dev shell); the flag keeps commits working on branches older than the config. Hooks live in `.pre-commit-config.yaml`; `prek run --all-files` runs them by hand. The flake8 hook matches `writePython3Bin`'s build-time flags: plain `flake8` ignores W503, the build does not, and that has broken the `ali-desktop` build more than once.

### Common NixOS Operations

```bash
# Build specific host configuration
nix build ".#nixosConfigurations.<hostname>.config.system.build.toplevel"

# Check flake (slow: evaluates every host's toplevel + builds all `checks`)
nix flake check

# Fast sanity check for routine iteration (modules/overlays/devShells/packages
# only, no host evaluation) -- same script CI's flake-check job runs
just check

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
  - `hosts/`: one **dir** per host (NixOS/Darwin/standalone home-manager). Each: `default.nix` (flake-parts module), `hardware-configuration.nix` (-> `flake.nixosModules.<hostname>-hardware`), `disko-config.nix` (-> `flake.nixosModules.<hostname>-disko-config`)
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
2. `hardware-configuration.nix`: -> `flake.nixosModules.<hostname>-hardware`
3. `disko-config.nix`: -> `flake.nixosModules.<hostname>-disko-config`

Custom modules via `self.nixosModules.*` (exported in `nixos-modules.nix`), enabled `modules.<name>.enable = true`. Home modules via `self.homeModules.*`. Secret/patch paths via `self + "/path"`. No relative imports (`../../`) -- all via flake outputs. New `flake-modules/` files auto-discovered by haumea.

`modules/base` options under `modules.base`:
- `enable`; `bootLoader` (enum `"systemd-boot"` / `"grub"` / `"secure-boot"` = Lanzaboote+TPM); `pcr15Value` (TPM PCR15 for LUKS, required when secure-boot)
- `enableImpermanence`, `impermanencePersistencePath` (default `/persistence`)
- `enableCachyOSKernel`
- `enableOpenSSH`, `enableTailscale`, `enableIPv6`, `enableICMPPing`
- `suspendState` (`"mem"` / `"standby"` / `"freeze"` / `null`), `hibernateMode` (`"platform"` / `"shutdown"`)
- `timezone`, `consoleKeyMap`
- `beesdFilesystems` (btrfs dedup)

### Key Systems

- **Overlays** (system-independent, channel access): `pkgs.stable` (nixpkgs 26.05), `pkgs.unstable` (nixos-unstable), `pkgs.master` (master). In `overlays/default.nix`, exported `flake-modules/overlays.nix`, applied per-host.
- **Impermanence**: some hosts tmpfs root + selective persistence; per-host paths.
- **Secrets Management**: sops-nix with age encryption. Keys + path rules in `.sops.yaml`.
- **Remote Deployment**: `deploy` attr via deploy-rs, in `flake-modules/deploy.nix`.

### Active Hosts

- **Desktop/Laptop**: `ali-desktop`, `ali-framework-laptop`, `ali-work-laptop`, `ali-mba-linux` (M1 MacBook Air, NixOS-on-Asahi, aarch64-linux)
- **macOS**: `Alisons-MacBook-Pro` (Darwin, work)
- **Servers**: `home-storage-server-1`, `home-kvm-hypervisor-1`, `home-k8s-master-1`, `home-k8s-server-1`, `home-vpn-gateway-1`, `download-server-1`
- **Dev/Test**: `dev-vm` (aarch64-linux VM)
- **Home-Manager Only**: `ali` (Arch Linux), `deck` (Steam Deck)

### Notable Flake Inputs

`ali-neovim` (custom neovim flake), `home-manager`, `stylix` (theming), `plasma-manager`, `sops-nix`, `disko`, `lanzaboote` (Secure Boot), `impermanence`, `deploy-rs`, `nixos-hardware` (e.g. Framework 16), `nixos-cosmic`, `rust-overlay`, `jovian-nixos` (Steam Deck), `niks3` (self-hosted binary cache push).

### CI/CD Workflows

- **`build-and-cache.yaml`**: builds all nixosConfigurations on push to main -> niks3 cache. Dry-run skips cached; parallel build+push via queue drain.
- **`update.yaml`**: daily flake lock update (2 AM UTC)
- **`ami-build-and-upload.yaml`**: builds+uploads NixOS AMIs to AWS, retention cleanup
- **`closure-report.yaml`**: closure size reports for desktop/laptop configs

### Subsystems

Detail in `docs/subsystems.md`; read the entry before touching the code.

- **Modpack & Modding**: `minecraft-modpack-packaging` (`pkgs/create-*-server`), `beatsaber-modding` (`pkgs/beatsaber-mods`, `home/modules/beatsaber`), `helldivers2-modding` (`pkgs/arsenal`, `pkgs/hd2-repatcher`, `home/modules/helldivers2-mods`).
- **Pins** (`pins/registry.json`, `scripts/pins.py`, skill `.claude/skills/pins`, ADR 0051): every pinned flake input, insecure-package permit and overlay version override is registered with a reason, a review deadline and a probe. Read the skill before adding, extending or removing a pin; CI fails a pin without an entry.
- **`modules.memoryRecall`** (`home/modules/memory-recall`, `scripts/retrieval-eval`): `docs/memory-recall.md`, ADRs 0029, 0030.
- **`claude-monitor`** (AI control centre): `docs/ai-control-centre.md`, ADRs 0040, 0041.
- **`modules.observabilityStack`** (`home/modules/observability-stack`, `scripts/token-tools`): `docs/observability-stack.md`, ADRs 0034, 0035, 0037.
- **Kernel livepatch** (`scripts/livepatch`, skill `.claude/skills/kernel-livepatch`): hand-written rebootless kernel patches for the Hetzner nodes (x86_64, `CONFIG_LIVEPATCH`).
- **`modules.rustBuildCache`** (`home/modules/rust-build-cache`): ADR 0043.

## Development Workflow

How to modify configs (test, build, switch, deploy), add a host or module, and manage secrets: the `nix-config-workflows` skill (`.claude/skills/nix-config-workflows/SKILL.md`). It carries the full steps.

### Pending Work
Pending / unfinished work (niks3 cache-push enablement, emulation module follow-ups) -> `PENDING.md` (repo root).

## Code Style

### Imports & Structure
Module arguments are `{ config, inputs, outputs, pkgs, lib, system, username, ... }`. Import rules (flake outputs only, no `../../`) are under Configuration Pattern.

### Naming Conventions
- **Files/Directories**: kebab-case (`modules/`, `ali-desktop/`)
- **Variables**: camelCase (`enableImpermanence`, `useSecureBoot`)
- **Hosts**: kebab-case (`home-storage-server-1`)

### Patterns
- Use `lib.mkIf`, `lib.mkDefault`, `lib.mkForce` for conditional config
- Merge with `//` operator for optional features
- Parameterize modules with sensible defaults
- Structure: base modules -> feature modules -> host-specific -> home-manager

### Error Handling
- Rely on Nix's built-in error reporting
- Use conditional feature flags instead of explicit error handling
- Check path existence with `lib.optional (builtins.pathExists ...)`

### Security
- Secrets managed via sops-nix with age encryption
- SSH key separation and proper authorizedKeys config
- Secure defaults (disable password auth, minimal open ports)
