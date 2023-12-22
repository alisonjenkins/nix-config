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
    dig
    discord
    ethtool
    fd
    fzf
    gamemode
    gamescope_git
    gcc-unwrapped
    git
    glxinfo
    gnupg
    google-chrome
    htop
    just
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
    pinentry
    proton-ge-custom
    psmisc
    pwgen
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

    gamemode = {
      enable = true;
      settings = {
        general = {
          defaultgov = "powersave";
          desiredgov = "performance";
          softrealtime = "auto";
          ioprio = 0;
          renice = 10;
        };

        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
        };
      };
    };
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
