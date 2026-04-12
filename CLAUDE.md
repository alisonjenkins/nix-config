---
id: CLAUDE
aliases:
  - CLAUDE.md
tags: []
---
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS and nix-darwin flake configuration managing multiple machines including desktops, laptops (Framework and work), servers (storage, K8s, VPN gateway, KVM hypervisor), and macOS systems. The configuration uses home-manager for user-level configuration and supports both NixOS and Darwin systems.

## Common Commands

### Building and Switching

All commands are managed via `just` (justfile). The system automatically uses `nh` if available, otherwise falls back to `nixos-rebuild` or `darwin-rebuild`:

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

This repository uses the **Dendritic Pattern** with **flake-parts** + **haumea** for modular, auto-discovered configuration.

### Directory Structure

- **`flake.nix`**: Minimal entry point (~50 lines of outputs logic). Defines inputs, uses haumea to auto-discover all flake-parts modules from `flake-modules/`.
- **`flake-modules/`**: All flake output definitions, auto-discovered by haumea:
  - `overlays.nix`: Exports `flake.overlays` from `overlays/`
  - `deploy.nix`: deploy-rs node definitions and checks
  - `dev-shells.nix`: Development shell (`perSystem.devShells.default`)
  - `templates.nix`: Flake templates
  - `nixos-modules.nix`: Exports all NixOS modules as `flake.nixosModules.*`
  - `home-modules.nix`: Exports home-manager modules as `flake.homeModules.*`
  - `hosts/`: One **directory** per host configuration (NixOS, Darwin, standalone home-manager), each containing `default.nix` (the flake-parts module), `hardware-configuration.nix` (wrapped as `flake.nixosModules.<hostname>-hardware`), and `disko-config.nix` (wrapped as `flake.nixosModules.<hostname>-disko-config`)
- **`modules/`**: Reusable NixOS modules using the **options system** (`options.*` / `config = mkIf cfg.enable`):
  - `base/`: Core system configuration (networking, boot, nix settings, impermanence, secure boot)
  - `desktop/`: Desktop environment configurations
  - `development/`: Development tools and environments (e.g., web development)
  - `locale/`: Localization settings
  - `libvirtd/`, `vr/`, `rocm/`, `ollama/`, `servers/`: Specialized functionality modules
  - `desktop-base/`, `desktop-1password/`, `desktop-aws-tools/`, `desktop-kubernetes/`, etc.: Desktop feature modules
  - `desktop-greetd/`, `desktop-greetd-regreet/`, `desktop-sddm/`: Display manager modules
  - `desktop-wm-plasma6/`, `desktop-wm-sway/`: Window manager modules
  - `hardware-fingerprint/`, `hardware-touchpad/`: Hardware feature modules
  - `k8s-master/`, `storage-server/`: Server role modules
- **`home/`**: Home-manager configurations:
  - `home-linux.nix`, `home-macos.nix`, `home-common.nix`: Platform-specific and shared configs
  - `programs/`: Per-program home-manager configurations (zsh, neovim, tmux, git, etc.)
  - `wms/`: Window manager configurations (river, plasma, etc.)
- **`pkgs/`**: Custom packages and overrides
- **`overlays/`**: System-independent nixpkgs overlays (accepts only `{ inputs }`, uses `final.stdenv.hostPlatform.system` internally)
- **`secrets/`**: SOPS-encrypted secrets (managed by sops-nix, configured in .sops.yaml)
- **`templates/`**: Flake templates (e.g., Rust development environment)

### Configuration Pattern

Each host is defined in its own flake-parts module directory at `flake-modules/hosts/<hostname>/`. These directories contain:

1. `default.nix`: The flake-parts module defining `flake.nixosConfigurations.<hostname>` (or `darwinConfigurations`/`homeConfigurations`)
2. `hardware-configuration.nix`: Wrapped as a flake-parts module exporting `flake.nixosModules.<hostname>-hardware`
3. `disko-config.nix`: Wrapped as a flake-parts module exporting `flake.nixosModules.<hostname>-disko-config`

All custom modules are referenced via `self.nixosModules.*` (exported in `nixos-modules.nix`) and enabled with `modules.<name>.enable = true`. Home-manager modules are referenced via `self.homeModules.*` (exported in `home-modules.nix`). File paths for secrets/patches use `self + "/path/to/file"`. No relative path imports (`../../`) are used — everything goes through flake outputs.

New flake-modules files are **auto-discovered** by haumea - just create a `.nix` file or directory in `flake-modules/` and it will be imported automatically.

The `modules/base` module uses NixOS options under `modules.base`:
- `enable`: Enable the base module
- `bootLoader`: Boot loader selection — enum of `"systemd-boot"`, `"grub"`, or `"secure-boot"` (Lanzaboote with TPM)
- `pcr15Value`: TPM PCR15 value for LUKS unlocking (required when `bootLoader = "secure-boot"`)
- `enableImpermanence`: Enable tmpfs root with persistence
- `impermanencePersistencePath`: Where to persist data (default: `/persistence`)
- `enableCachyOSKernel`: Enable CachyOS kernel overlay (for hosts using CachyOS kernel packages)
- `enableOpenSSH`, `enableTailscale`, `enableIPv6`, `enableICMPPing`: Feature toggles
- `suspendState`: Suspend state (`"mem"`, `"standby"`, `"freeze"`, or `null` for auto-detect)
- `hibernateMode`: Hibernate mode (`"platform"` or `"shutdown"`)
- `timezone`, `consoleKeyMap`: Locale settings
- `beesdFilesystems`: Btrfs dedup filesystem configuration

### Key Systems

**Overlays**: The flake provides system-independent overlays for accessing different nixpkgs channels:
- `pkgs.stable`: nixpkgs 25.11 stable
- `pkgs.unstable`: nixos-unstable
- `pkgs.master`: nixpkgs master branch

Configured in `overlays/default.nix` and exported via `flake-modules/overlays.nix`. Applied per-host in their flake-parts module files.

**Impermanence**: Several hosts use tmpfs root filesystems with selective persistence via the impermanence module. Persistence paths are configured per-host.

**Secrets Management**: Uses sops-nix with age encryption. Age keys are defined in `.sops.yaml` with path-based rules for different hosts/secrets.

**Remote Deployment**: The flake exports a `deploy` attribute using deploy-rs for remote system deployments, defined in `flake-modules/deploy.nix`.

### Active Hosts

Key configurations defined in the flake:
- **Desktop/Laptop**: `ali-desktop`, `ali-framework-laptop`, `ali-work-laptop`
- **macOS**: `Alisons-MacBook-Pro` (Darwin configuration for work laptop)
- **Servers**: `home-storage-server-1`, `home-kvm-hypervisor-1`, `home-k8s-master-1`, `home-k8s-server-1`, `home-vpn-gateway-1`, `download-server-1`
- **Dev/Test**: `dev-vm` (aarch64-linux VM)
- **Home-Manager Only**: `ali` (Arch Linux), `deck` (Steam Deck)

### Notable Flake Inputs

- `ali-neovim`: Custom Neovim configuration flake
- `home-manager`: User environment management
- `stylix`: System-wide theming
- `plasma-manager`: KDE Plasma home-manager integration
- `sops-nix`: Secrets management
- `disko`: Declarative disk partitioning
- `lanzaboote`: Secure Boot support
- `impermanence`: Tmpfs root persistence
- `deploy-rs`: Remote deployment tool
- `nixos-hardware`: Hardware-specific configurations (e.g., Framework 16)
- `nixos-cosmic`: Alternative desktop environment
- `rust-overlay`: Rust toolchain management
- `jovian-nixos`: Steam Deck specific configurations
- `niks3`: Self-hosted binary cache push tool

### CI/CD Workflows

- **`build-and-cache.yaml`**: Builds all nixosConfigurations on push to main and pushes to niks3 binary cache. Includes dry-run check to skip cached builds and parallel build+push via queue drain.
- **`update.yaml`**: Automated daily flake lock updates (2 AM UTC)
- **`ami-build-and-upload.yaml`**: Builds and uploads NixOS AMIs to AWS with retention cleanup
- **`closure-report.yaml`**: Generates closure size reports for desktop/laptop configurations

### Pending: niks3 cache push on desktops/laptops

The `modules/niks3-cache-push` module and GHA parallel push workflow are implemented but **not yet enabled** on hosts. To finish:

1. Create `secrets/niks3-token.enc.yaml` via `sops secrets/niks3-token.enc.yaml` with key `niks3_token`
2. Add ali-framework-laptop's server age key to `.sops.yaml` (keys section + niks3-token creation rule)
3. Uncomment the `modules.niks3CachePush` and `sops.secrets.niks3-token` blocks in:
   - `flake-modules/hosts/ali-desktop/default.nix`
   - `flake-modules/hosts/ali-framework-laptop/default.nix`
   - `flake-modules/hosts/ali-work-laptop/default.nix`

## Development Workflow

When modifying configurations:
1. Edit relevant files in `modules/`, `home/`, or `flake-modules/hosts/<hostname>/`
2. Test changes with `just test` for temporary activation
3. Use `just build` to build without activating (useful for checking for errors)
4. Commit with `just switch` to activate and make permanent
5. For remote hosts, use `just deploy .#<hostname>` after testing locally

When adding new hosts:
1. Create a directory at `flake-modules/hosts/<hostname>/` (auto-discovered by haumea)
2. Create `default.nix` as a flake-parts module defining `flake.nixosConfigurations.<hostname>`
3. Create `hardware-configuration.nix` wrapped as `{ ... }: { flake.nixosModules.<hostname>-hardware = { ... }; }`
4. Create `disko-config.nix` wrapped as `{ ... }: { flake.nixosModules.<hostname>-disko-config = { ... }; }`
5. Reference custom modules via `self.nixosModules.*`, home modules via `self.homeModules.*`, secrets via `self + "/secrets/..."`, and overlays via `self.overlays.*`
6. New files must be `git add`ed before `nix eval`/`nix build` will see them (flake git tracking)

When adding new NixOS modules (two-step process):
1. Create the module in `modules/<name>/default.nix` using the options pattern
2. Export it in `flake-modules/nixos-modules.nix` (add an entry to `flake.nixosModules`)
3. Reference it in host files via `self.nixosModules.<name>`
4. New files in `modules/` must be `git add`ed before `nix eval`/`nix build` will see them (flake git tracking)

When adding new flake-modules:
1. Create a `.nix` file in `flake-modules/` or `flake-modules/hosts/`
2. The file will be auto-discovered by haumea - no need to update `flake.nix`
3. Use the flake-parts module signature: `{ inputs, self, ... }: { flake = { ... }; }`

When adding secrets:
1. Add age keys to `.sops.yaml` if needed
2. Create secret files in `secrets/` or `secrets/<hostname>/`
3. Unencrypted Secrets should be named using the pattern `<name>.dec.yaml` so that they are gitignored. Encrypted secrets get saved with the name pattern `<name>.enc.yaml`
4. Encrypt with `sops` command
5. Reference in host configuration via `sops.secrets.<name>`
