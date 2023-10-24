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
    gcc-unwrapped
    git
    glxinfo
    htop
    kbfs
    keybase
    keybase-gui
    lshw
    neovim
    nnn
    ripgrep
    rustc
    starship
    stow
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
