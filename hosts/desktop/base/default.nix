{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      theme = "breeze";
    };
    kernelParams = [ "quiet" ];
  };

  environment.systemPackages = with pkgs; [
    bat
    cargo
    fd
    fzf
    git
    htop
    kbfs
    keybase
    keybase-gui
    neovim
    nnn
    ripgrep
    rustc
    tmux
    zsh
  ];

  services = {
    kbfs = {
      enable = true;
    };
    keybase = {
      enable = true;
    };
  };
}
