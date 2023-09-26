<p align="center"><img src="https://i.imgur.com/X5zKxvp.png" width=300px></p>

<p align="center">
<a href="https://nixos.org/"><img src="https://img.shields.io/badge/NixOS-Unstable-informational.svg?style=flat&logo=nixos&logoColor=CAD3F5&colorA=24273A&colorB=8AADF4"></a>

<h2 align="center">Alison Jenkins NixOS Dotfiles</h2>

### Apps:

|                          |             NixOS 23.11                               |
|--------------------------|:-----------------------------------------------------:|
| **Desktop Environment**  |   [Hyprland](https://hyprland.org)                    |
| **Terminal Emulator**    |   [Alacritty](https://github.com/alacritty/alacritty) |
| **Display Server**       |   [Wayland](https://wayland.freedesktop.org)          |
| **Application Launcher** |   [Rofi](https://github.com/davatorium/rofi)          |
| **Shell**                |   [Zsh](https://zsh.sourceforge.io)                   |
| **Text Editor**          |   [Neovim](https://neovim.io)                         |


### DE/WM

**Hyprland**

Desktop Environment:

## Nix Dotfiles Directory Structure
```
├── home
│  ├── programs
│  │   ├── alacritty
│  │   ├── hypr
│  │   ├── kitty
│  │   ├── rofi
│  │   ├── waybar
│  │   └── zsh
│  ├── scripts
│  ├── themes
│  │   └── cava
│  ├── wallpapers
│  └── home.nix
├── host
│  └── desktop
│      └── fonts
│      └── virtualisation
├── nixos
│  ├── configuration.nix
│  └── hardware-configuration.nix
├── flake.nix
└── install-ali-desktop.sh
```

### Installation

0. Download the project:
```bash
 $ git clone https://github.com/alisonjenkins/nix-config.git && cd nix-config
```

1. Install the project:

```bash
$ chmod +x install-ali-desktop.sh
$ ./install-ali-desktop.sh
```
or

```bash
$ cd nix-config
$ sudo nixos-rebuild switch --flake .#ali
```
