{ pkgs, inputs, system, ... }:
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
    bc
    beancount
    cargo
    chromium
    comma
    corectrl
    crunchy-cli
    dig
    discord
    ethtool
    fava
    fd
    fzf
    gamemode
    gamescope_git
    gcc-unwrapped
    gimp
    git
    glxinfo
    gnupg
    google-chrome
    gtk3
    haveged
    htop
    inputs.ali-neovim.packages.${system}.nvim
    iotop
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
    nushellFull
    parted
    pinentry
    proton-ge-custom
    psmisc
    pwgen
    ripgrep
    rng-tools
    rustc
    sops
    starship
    stdenv.cc.cc.lib
    steamtinkerlaunch
    stow
    tig
    tmux
    usbutils
    virt-manager
    vulkan-tools
    xdg-utils
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
    atd.enable = true;
    cpupower-gui.enable = true;
    haveged.enable = true;
    kbfs.enable = true;
    keybase.enable = true;

    avahi = {
      enable = true;
      nssmdns = true;
      openFirewall = true;
    };

    flatpak = {
      enable = true;
      packages = [
        "de.shorsh.discord-screenaudio"
      ];
      remotes = [{
        name = "flathub-beta";
        location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
      }];
      update = {
        onActivation = true;
        auto = {
          enable = true;
          onCalendar = "daily";
        };
      };
    };

    printing = {
      enable = true;
    };
  };
}
