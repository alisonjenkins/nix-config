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
    fd
    fzf
    git
    htop
    neovim
    nnn
    ripgrep
    tmux
    zsh
  ];
}
