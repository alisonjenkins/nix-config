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
    age
    bat
    cargo
    chromium
    comma
    discord
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
    keyutils
    libkrb5
    libpng
    libpulseaudio
    libreoffice
    libvorbis
    lshw
    luxtorpeda
    mangohud32_git
    mangohud_git
    mesa32_git
    mesa_git
    mpv-vapoursynth
    ncdu
    nnn
    parted
    proton-ge-custom
    psmisc
    ripgrep
    rustc
    sops
    starship
    stdenv.cc.cc.lib
    stow
    tig
    tmux
    vulkan-tools
    xorg.libXScrnSaver
    xorg.libXcursor
    xorg.libXi
    xorg.libXinerama
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
    cpupower-gui.enable = true;
    flatpak.enable = true;
    kbfs.enable = true;
    keybase.enable = true;
  };
}
