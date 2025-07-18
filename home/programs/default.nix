{ pkgs, inputs, lib, username, system, gpuType, config, gitUserName, gitEmail, gitGPGSigningKey, ... }: {
  imports = [
    # ./batsignal
    # ./dunst
    # ./kubecolor
    (import ./alacritty { inherit username system inputs lib pkgs config; })
    (import ./gcc { inherit pkgs username; })
    (import ./git { inherit pkgs inputs lib username gitUserName gitEmail gitGPGSigningKey; })
    (import ./keybase { inherit username system inputs lib pkgs config; })
    (import ./obsidian { inherit username system inputs lib pkgs config; })
    (import ./ollama { inherit gpuType pkgs; })
    (import ./opencommit { inherit pkgs; })
    (import ./quickshell { inherit config pkgs system inputs; })
    (import ./tmux { inherit username pkgs; })
    ./aerospace
    ./alacritty
    ./aws
    ./bat
    ./broot
    ./carapace
    ./chromium
    ./comodoro
    ./direnv
    ./eww
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
    ./opentofu
    ./rio
    ./rofi
    ./rust
    ./ssh
    ./starship
    ./terraform
    ./tmux
    ./yambar
    ./yazi
    ./zk
    ./zoxide
    ./zq
    ./zsh
  ];
}
