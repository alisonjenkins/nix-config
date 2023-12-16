{ pkgs, ... }:
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
    chromium
    comma
    fd
    fzf
    gamescope_git
    gcc-unwrapped
    git
    glxinfo
    google-chrome
    htop
    kbfs
    keybase
    keybase-gui
    lshw
    mpv-vapoursynth
    ncdu
    neovim
    nnn
    proton-ge-custom
    ripgrep
    rustc
    starship
    stow
    tig
    tmux
    vulkan-tools
    yuzu-early-access_git
    zoom-us
    zsh
  ];

  programs = {
    partition-manager.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
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
