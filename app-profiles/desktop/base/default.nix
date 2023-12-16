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
    comma
    fd
    fzf
    gcc-unwrapped
    git
    glxinfo
    htop
    kbfs
    keybase
    keybase-gui
    lshw
    ncdu
    neovim
    nnn
    ripgrep
    rustc
    starship
    stow
    tig
    tmux
    vulkan-tools
    zoom-us
    zsh
  ];

  hardware = {
    bluetooth = {
      enable = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
        };
      };
    };
  };

  services = {
    flatpak.enable = true;
    kbfs.enable = true;
    keybase.enable = true;
  };
}
