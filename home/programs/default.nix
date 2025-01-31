{ pkgs, inputs, lib, username, system, gpuType, config, gitUserName, gitEmail, gitGPGSigningKey, ... }: {
  imports = [
    # ./dunst
    # ./kubecolor
    (import ./alacritty { inherit username system inputs lib pkgs config; })
    (import ./firefox { inherit username lib pkgs; })
    (import ./gcc { inherit pkgs username; })
    (import ./git { inherit pkgs inputs lib username gitUserName gitEmail gitGPGSigningKey; })
    (import ./ollama { inherit gpuType pkgs; })
    (import ./opencommit { inherit pkgs; })
    (import ./tmux { inherit username pkgs; })
    ./aerospace
    ./alacritty
    ./aws
    ./bat
    ./batsignal
    ./broot
    ./carapace
    ./comodoro
    ./direnv
    ./eww
    ./firefox
    ./fzf
    ./fzf
    ./gcc
    ./gh
    ./gh
    ./gh-dash
    ./ghostty
    ./gitui
    ./go
    ./granted
    ./hyfetch
    ./info
    ./jq
    ./k9s
    ./kitty
    ./kwalletd
    ./lsd
    ./man
    ./mcfly
    ./mimetypes
    ./neovim
    ./newsboat
    ./nix-index
    ./noti
    ./nushell
    ./obs
    ./rofi
    ./rust
    ./ssh
    ./starship
    ./tmux
    ./waybar
    ./yambar
    ./yazi
    ./zoxide
    ./zq
    ./zsh
  ];
}
