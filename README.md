<p align="center"><img src="https://i.imgur.com/X5zKxvp.png" width=300px></p>

<p align="center">
<a href="https://nixos.org/"><img src="https://img.shields.io/badge/NixOS-Unstable-informational.svg?style=flat&logo=nixos&logoColor=CAD3F5&colorA=24273A&colorB=8AADF4"></a>

<h2 align="center">Alison Jenkins NixOS Dotfiles</h2>

### Apps:

|                          |             NixOS 24.05                               |
|--------------------------|:-----------------------------------------------------:|
| **Desktop Environment**  |   [KDE Plasma 6](https://kde.org/announcements/megarelease/6/)                    |
| **Terminal Emulator**    |   [Alacritty](https://github.com/alacritty/alacritty) |
| **Display Server**       |   [Wayland](https://wayland.freedesktop.org)          |
| **Application Launcher** |   [Rofi](https://github.com/davatorium/rofi)          |
| **Shell**                |   [Zsh](https://zsh.sourceforge.io)                   |
| **Text Editor**          |   [Neovim](https://neovim.io)                         |


### Installation

0. Download the project:
```bash
 $ git clone https://github.com/alisonjenkins/nix-config.git && cd nix-config
```

1. Install the project:

```bash
$ cd nix-config
$ sudo nixos-rebuild switch --flake .#host
```
