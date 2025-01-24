{ pkgs, inputs, lib, username, user_configs, system, ... }: {
  imports = [
    # ./dunst
    # ./kubecolor
    ./aerospace
    (import ./alacritty { inherit username system inputs lib pkgs; })
    ./aws
    ./bat
    ./batsignal
    ./broot
    ./carapace
    ./comodoro
    ./direnv
    ./eww
    (import ./firefox { inherit username lib pkgs; })
    ./fzf
    (import ./gcc { inherit pkgs username; })
    ./gh
    ./gh-dash
    ./ghostty
    (import ./git { inherit pkgs inputs lib username user_configs; })
    ./gitui
    ./go
    ./granted
    ./hyfetch
    ./info
    ./jq
    (import ./k9s { inherit username pkgs; })
    ./kitty
    ./kwalletd
    ./lsd
    ./man
    ./mcfly
    ./mimetypes
    ./neovim
    ./newsboat
    # ./nix-index
    ./noti
    ./nushell
    ./obs
    ./rofi
    ./rust
    ./ssh
    ./starship
    (import ./tmux { inherit username pkgs; })
    ./waybar
    ./yambar
    ./yazi
    ./zoxide
    ./zq
    ./zsh
  ];
}
