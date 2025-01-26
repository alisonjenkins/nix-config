{ pkgs, inputs, lib, username, program_configs, system, gpuType, ... }: {
  imports = [
    # ./dunst
    # ./kubecolor
    # ./nix-index
    (import ./alacritty { inherit username system inputs lib pkgs; })
    (import ./firefox { inherit username lib pkgs; })
    (import ./gcc { inherit pkgs username; })
    (import ./git { inherit pkgs inputs lib username program_configs; })
    (import ./k9s { inherit username pkgs; })
    (import ./ollama { inherit gpuType pkgs; })
    (import ./opencommit { inherit pkgs; })
    (import ./tmux { inherit username pkgs; })
    ./aerospace
    ./aws
    ./bat
    ./batsignal
    ./broot
    ./carapace
    ./comodoro
    ./direnv
    ./eww
    ./fzf
    ./gh
    ./gh-dash
    ./ghostty
    ./gitui
    ./go
    ./granted
    ./hyfetch
    ./info
    ./jq
    ./kitty
    ./kwalletd
    ./lsd
    ./man
    ./mcfly
    ./mimetypes
    ./neovim
    ./newsboat
    ./noti
    ./nushell
    ./obs
    ./rofi
    ./rust
    ./ssh
    ./starship
    ./waybar
    ./yambar
    ./yazi
    ./zoxide
    ./zq
    ./zsh
  ];
}
