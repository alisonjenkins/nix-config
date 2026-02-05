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

### Directory Structure

- **`flake.nix`**: Main entry point defining all system configurations (NixOS, Darwin, home-manager), inputs, and outputs
- **`hosts/`**: Per-machine configurations including hardware-configuration.nix and machine-specific settings
- **`modules/`**: Reusable NixOS modules organized by category:
  - `base/`: Core system configuration (networking, boot, nix settings, impermanence support)
  - `desktop/`: Desktop environment configurations
  - `development/`: Development tools and environments (e.g., web development)
  - `locale/`: Localization settings
  - `libvirtd/`, `vr/`, `rocm/`, `ollama/`, etc.: Specialized functionality modules
- **`app-profiles/`**: Composable application bundles that can be imported into hosts:
  - `desktop/`: Desktop-related profiles (AWS tools, display managers, window managers, local K8s, VR hardware)
  - `k8s-master/`, `kvm-server/`, `storage-server/`: Server role profiles
- **`home/`**: Home-manager configurations:
  - `home-linux.nix`: Linux user environment (imports home-common.nix + linux-specific programs)
  - `home-macos.nix`: macOS user environment (imports home-common.nix + macos-specific programs)
  - `home-common.nix`: Shared home-manager configuration
  - `programs/`: Per-program home-manager configurations (zsh, neovim, tmux, git, etc.)
  - `wms/`: Window manager configurations (hyprland, plasma, etc.)
- **`pkgs/`**: Custom packages and overrides (wallpapers, scripts like git-clean, lock-session, suspend-scripts)
- **`overlays/`**: Nixpkgs overlays providing stable/unstable/master package sets and package modifications
- **`secrets/`**: SOPS-encrypted secrets (managed by sops-nix, configured in .sops.yaml)
- **`templates/`**: Flake templates (e.g., Rust development environment)

### Configuration Pattern

Hosts are defined in `flake.nix` under `nixosConfigurations`, `darwinConfigurations`, or `homeConfigurations`. Each host configuration:

1. Imports base modules from `modules/base` with configuration options (impermanence, secure boot, etc.)
2. Imports relevant app-profiles from `app-profiles/`
3. Imports host-specific configuration from `hosts/<hostname>/configuration.nix`
4. Configures home-manager as a NixOS/Darwin module, pointing to home configurations in `home/`

The `modules/base` module accepts important parameters:
- `enableImpermanence`: Enable tmpfs root with persistence
- `impermanencePersistencePath`: Where to persist data (default: `/persistence`)
- `useSecureBoot`: Enable Lanzaboote secure boot with TPM
- `pcr15Value`: TPM PCR15 value for LUKS unlocking
- `useSystemdBoot`/`useGrub`: Boot loader selection
- `enableOpenSSH`, `enablePlymouth`, `enableIPv6`: Feature toggles
- `timezone`, `consoleKeyMap`: Locale settings

### Key Systems

**Overlays**: The flake provides multiple overlays for accessing different nixpkgs channels:
- `pkgs.stable`: nixpkgs 25.11 stable
- `pkgs.unstable`: nixos-unstable
- `pkgs.master`: nixpkgs master branch

These are configured in `overlays/default.nix` and applied in `flake.nix`.

**Impermanence**: Several hosts use tmpfs root filesystems with selective persistence via the impermanence module. Persistence paths are configured per-host.

**Secrets Management**: Uses sops-nix with age encryption. Age keys are defined in `.sops.yaml` with path-based rules for different hosts/secrets.

**Remote Deployment**: The flake exports a `deploy` attribute using deploy-rs for remote system deployments. Target hosts and their configurations are defined in `flake.nix` under the `deploy.nodes` attribute.

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
1. Create directory in `hosts/<hostname>/`
2. Add `configuration.nix` and `hardware-configuration.nix`
3. Import appropriate modules and app-profiles
4. Add to `nixosConfigurations` in `flake.nix`
5. Configure home-manager for the user

When adding secrets:
1. Add age keys to `.sops.yaml` if needed
2. Create secret files in `secrets/` or `secrets/<hostname>/`
3. Unencrypted Secrets should be named using the pattern `<name>.dec.yaml` so that they are gitignored. Encrypted secrets get saved with the name pattern `<name>.enc.yaml`
4. Encrypt with `sops` command
5. Reference in host configuration via `sops.secrets.<name>`
