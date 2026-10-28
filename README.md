# nix-config

NixOS and nix-darwin flake for desktops, laptops, servers and macOS machines, built with flake-parts and home-manager.

<p align="center"><img src="https://i.imgur.com/X5zKxvp.png" alt="nix-config logo" width="300px"></p>

<p align="center"><a href="https://nixos.org/"><img src="https://img.shields.io/badge/NixOS-Unstable-informational.svg?style=flat&logo=nixos&logoColor=CAD3F5&colorA=24273A&colorB=8AADF4" alt="NixOS unstable"></a></p>

## Hosts

| Host | Role | Platform |
| --- | --- | --- |
| `ali-desktop` | Desktop | NixOS |
| `ali-framework-laptop` | Laptop | NixOS |
| `ali-work-laptop` | Laptop | NixOS |
| `ali-mba-linux` | Laptop (M1 MacBook Air) | NixOS (aarch64-linux) |
| `Alisons-MacBook-Pro` | Work laptop | macOS (Darwin) |
| `home-storage-server-1` | Storage server | NixOS |
| `home-kvm-hypervisor-1` | KVM hypervisor | NixOS |
| `home-k8s-master-1` | K8s master | NixOS |
| `home-k8s-server-1` | K8s server | NixOS |
| `home-vpn-gateway-1` | VPN gateway | NixOS |
| `download-server-1` | Download server | NixOS |
| `dev-vm` | Dev/test VM | NixOS (aarch64-linux) |
| `ali` | Home-manager only | Arch Linux |
| `deck` | Home-manager only | Steam Deck |

## Quickstart

Clone the repository:

```bash
git clone https://github.com/alisonjenkins/nix-config.git && cd nix-config
```

Build and switch:

```bash
just switch
```

Use `just build` to build without activating, and `just check` for a fast sanity check. The host is selected by hostname; for a specific host:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

## Layout

- `flake-modules/`: Flake-parts modules auto-discovered by haumea.
- `modules/`: Reusable NixOS system modules.
- `home/`: Home-manager configurations and per-program modules.
- `pkgs/`: Custom package definitions and overrides.
- `overlays/`: System-independent nixpkgs overlays.
- `secrets/`: SOPS-encrypted secrets managed via age.
- `templates/`: Flake templates for project initialization.

## Documentation

- [docs index](./docs/README.md)
- [Subsystems](./docs/subsystems.md)
- [Architecture decisions](./docs/adr/)
- [CLAUDE.md](./CLAUDE.md)
