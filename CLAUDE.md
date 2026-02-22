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
  - `nixos-modules.nix`: Exports all NixOS modules and app-profiles as `flake.nixosModules.*`
  - `home-modules.nix`: Exports home-manager modules as `flake.homeModules.*`
  - `hosts/`: One file per host configuration (NixOS, Darwin, standalone home-manager)
- **`hosts/`**: Per-machine configurations (hardware-configuration.nix, host-specific settings, module option values)
- **`modules/`**: Reusable NixOS modules using the **options system** (`options.*` / `config = mkIf cfg.enable`):
  - `base/`: Core system configuration (networking, boot, nix settings, impermanence, secure boot)
  - `desktop/`: Desktop environment configurations
  - `development/`: Development tools and environments (e.g., web development)
  - `locale/`: Localization settings
  - `libvirtd/`, `vr/`, `rocm/`, `ollama/`, `servers/`: Specialized functionality modules
- **`app-profiles/`**: Composable application bundles imported into hosts:
  - `desktop/`: Desktop-related profiles (AWS tools, display managers, window managers, local K8s, VR hardware)
  - `k8s-master/`, `kvm-server/`, `storage-server/`: Server role profiles
- **`home/`**: Home-manager configurations:
  - `home-linux.nix`, `home-macos.nix`, `home-common.nix`: Platform-specific and shared configs
  - `programs/`: Per-program home-manager configurations (zsh, neovim, tmux, git, etc.)
  - `wms/`: Window manager configurations (hyprland, plasma, etc.)
- **`pkgs/`**: Custom packages and overrides
- **`overlays/`**: System-independent nixpkgs overlays (accepts only `{ inputs }`, uses `final.stdenv.hostPlatform.system` internally)
- **`secrets/`**: SOPS-encrypted secrets (managed by sops-nix, configured in .sops.yaml)
- **`templates/`**: Flake templates (e.g., Rust development environment)

### Configuration Pattern

Each host is defined in its own flake-parts module at `flake-modules/hosts/<hostname>.nix`. These modules:

1. Import NixOS/app-profile modules via path imports from `../../modules/` and `../../app-profiles/`
2. Import host-specific configuration from `../../hosts/<hostname>/configuration.nix`
3. Configure module options in the host's `configuration.nix` (e.g., `modules.base.enable = true;`)
4. Configure home-manager as a NixOS/Darwin module

New flake-modules files are **auto-discovered** by haumea - just create a `.nix` file in `flake-modules/` and it will be imported automatically.

The `modules/base` module uses NixOS options under `modules.base`:
- `enable`: Enable the base module
- `enableImpermanence`: Enable tmpfs root with persistence
- `impermanencePersistencePath`: Where to persist data (default: `/persistence`)
- `useSecureBoot`: Enable Lanzaboote secure boot with TPM
- `pcr15Value`: TPM PCR15 value for LUKS unlocking
- `useSystemdBoot`/`useGrub`: Boot loader selection
- `enableOpenSSH`, `enablePlymouth`, `enableIPv6`: Feature toggles
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
- `niri-flake`, `nixos-cosmic`: Alternative desktop environments
- `rust-overlay`: Rust toolchain management
- `jovian-nixos`: Steam Deck specific configurations

## Development Workflow

When modifying configurations:
1. Edit relevant files in `modules/`, `app-profiles/`, `home/`, or `hosts/`
2. Test changes with `just test` for temporary activation
3. Use `just build` to build without activating (useful for checking for errors)
4. Commit with `just switch` to activate and make permanent
5. For remote hosts, use `just deploy .#<hostname>` after testing locally

When adding new hosts:
1. Create directory in `hosts/<hostname>/` with `configuration.nix` and `hardware-configuration.nix`
2. Create a flake-parts module at `flake-modules/hosts/<hostname>.nix` (auto-discovered by haumea)
3. In the flake-parts module, import NixOS/app-profile modules and the host configuration
4. In the host's `configuration.nix`, set module options (e.g., `modules.base.enable = true;`)
5. Configure home-manager in the flake-parts module if needed

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
