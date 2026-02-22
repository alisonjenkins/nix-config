{
  config,
  gitEmail,
  gitGPGSigningKey,
  gitUserName,
  github_clone_ssh_host_personal ? "github.com",
  github_clone_ssh_host_work ? "github.com",
  gpuType ? "",
  inputs,
  lib,
  pkgs,
  system,
  username,
  ...
}: {
  imports = [
    # ./batsignal
    # ./dunst
    # ./kubecolor
    ./aerospace
    ./alacritty
    ./aws
    ./bat
    ./broot
    ./carapace
    ./chromium
    ./claude-code
    ./comodoro
    ./direnv
    ./eww
    ./fish
    ./fzf
    ./gcc
    ./gh
    ./gh-dash
    ./ghostty
    ./git
    ./gitui
    ./go
    ./granted
    ./hyfetch
    ./info
    ./jq
    ./k9s
    ./keybase
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
    ./obsidian
    ./ollama
    ./opencommit
    ./opentofu
    ./quickshell
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
