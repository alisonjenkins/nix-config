{ pkgs
, inputs
, system
, ...
}: {
  imports = [
    ../1password
  ];

  boot = {
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
      ];
    };
    plymouth = {
      enable = true;
      # theme = "breeze";
    };
    kernelParams = [ "quiet" ];
  };

  programs.gamescope = {
    enable = true;
    capSysNice = false;
    # package = pkgs.gamescope_git;
  };

  services.xserver.deviceSection = ''
    Option "DRI" "3"
  '';

  environment.systemPackages = with pkgs; [
    # fava
    # ffmpeg
    # gamescope
    # inputs.jovian-nixos.legacyPackages.${system}.gamescope
    # mangohud32_git
    # mpv-vapoursynth
    age
    arrpc
    bat
    bc
    beancount
    bluez
    bluez-tools
    brightnessctl
    cachix
    cargo
    cargo-nextest
    cava
    chromium
    colmena
    comma
    corectrl
    curl
    ddcutil
    dig
    discord-canary
    droidcam
    dua
    element-desktop
    ethtool
    fd
    fish
    freeplane
    fzf
    gcc-unwrapped
    gimp
    git
    glxinfo
    gnupg
    google-chrome
    gtk3
    haveged
    htop
    imagemagick
    inputs.ali-neovim.packages.${system}.nvim
    iotop
    jdk17
    jq
    just
    kbfs
    kdePackages.filelight
    keybase
    keybase-gui
    keyutils
    kodi-wayland
    libkrb5
    libpng
    libpulseaudio
    libreoffice
    libvorbis
    lm_sensors
    lshw
    ncdu
    nh
    nix-fast-build
    nix-tree
    nushell
    obsidian
    parted
    pinentry
    psmisc
    pwgen
    ripgrep
    rng-tools
    rustc
    sops
    stdenv.cc.cc.lib
    stow
    tig
    tmux
    unrar
    unstable.ghostty
    usbutils
    virt-manager
    vmtouch
    vulkan-tools
    vulnix
    watchexec
    wine
    xdg-utils
    xorg.libXScrnSaver
    xorg.libXcursor
    xorg.libXi
    xorg.libXinerama
    yazi
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
    atd.enable = true;
    cpupower-gui.enable = true;
    haveged.enable = true;
    kbfs.enable = true;
    keybase.enable = true;

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    flatpak = {
      enable = true;
      packages = [
        "codes.merritt.Nyrna"
        "org.vinegarhq.Sober"
      ];
      remotes = [
        {
          name = "flathub";
          location = "https://flathub.org/repo/flathub.flatpakrepo";
        }
        {
          name = "flathub-beta";
          location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
        }
      ];
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
      drivers = [
        pkgs.brlaser
      ];
    };
  };
}
