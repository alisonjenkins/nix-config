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
    vulkan-tools
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

    opengl = {
      driSupport = true;
      driSupport32Bit = true;
      enable = true;
    };
  };

  services = {
    kbfs = {
      enable = true;
    };
    keybase = {
      enable = true;
    };
  };
}
