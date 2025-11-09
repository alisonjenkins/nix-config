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

No automated linting/formating tools configured.

## Architecture

### Directory Structure
- **`flake.nix`**: Main entry point defining all system configurations
- **`hosts/`**: Per-machine configurations (hardware-configuration.nix, machine-specific settings)
- **`modules/`**: Reusable NixOS modules (base, desktop, development, locale, specialized functionality)
- **`app-profiles/`**: Composable application bundles (desktop, server roles)
- **`home/`**: Home-manager configurations (programs, wms, themes, wallpapers)
- **`pkgs/`**: Custom packages and overrides
- **`overlays/`**: Nixpkgs overlays (stable/unstable/master package sets)
- **`secrets/`**: SOPS-encrypted secrets
- **`templates/`**: Flake templates

### Configuration Pattern
Host configurations follow this structure:
1. Import base modules from `modules/base` with configuration options
2. Import relevant app-profiles from `app-profiles/`
3. Import host-specific configuration from `hosts/<hostname>/configuration.nix`
4. Configure home-manager pointing to configurations in `home/`

### Key Systems
- **Overlays**: Multiple nixpkgs channels (stable, unstable, master)
- **Impermanence**: Tmpfs root filesystems with selective persistence
- **Secrets Management**: sops-nix with age encryption
- **Remote Deployment**: deploy-rs for remote system deployments

## Development Workflow

### Modifying Configurations
1. Edit relevant files in `modules/`, `app-profiles/`, `home/`, or `hosts/`
2. Test changes with `just test` for temporary activation
3. Use `just build` to build without activating (error checking)
4. Commit with `just switch` to activate and make permanent
5. For remote hosts, use `just deploy .#<hostname>` after local testing

### Adding New Hosts
1. Create directory in `hosts/<hostname>/`
2. Add `configuration.nix` and `hardware-configuration.nix`
3. Import appropriate modules and app-profiles
4. Add to `nixosConfigurations` in `flake.nix`
5. Configure home-manager for the user

### Managing Secrets
1. Add age keys to `.sops.yaml` if needed
2. Create secret files in `secrets/` or `secrets/<hostname>/`
3. Encrypt with `sops` command
4. Reference in host configuration via `sops.secrets.<name>`

## Code Style

### Imports & Structure
```nix
{ config, inputs, outputs, pkgs, lib, system, username, ... }:
imports = [
  inputs.external-module.nixosModules.module  # External inputs first
  ../../modules/base                          # Local modules
  ./hardware-configuration.nix               # Host-specific last
];
```

### Naming Conventions
- **Files/Directories**: kebab-case (`app-profiles/`, `ali-desktop/`)
- **Variables**: camelCase (`enableImpermanence`, `useSecureBoot`)
- **Hosts**: kebab-case (`home-storage-server-1`)

### Patterns
- Use `lib.mkIf`, `lib.mkDefault`, `lib.mkForce` for conditional config
- Merge with `//` operator for optional features
- Parameterize modules with sensible defaults
- Structure: base modules → app-profiles → host-specific → home-manager

### Error Handling
- Rely on Nix's built-in error reporting
- Use conditional feature flags instead of explicit error handling
- Check path existence with `lib.optional (builtins.pathExists ...)`

### Security
- Secrets managed via sops-nix with age encryption
- SSH key separation and proper authorizedKeys config
- Secure defaults (disable password auth, minimal open ports)