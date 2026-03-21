{ lib
, pkgs
, inputs
, ...
}: {
  imports = [
    ../1password
  ];

  modules.base.useAliNeovim = true;

  programs.gamescope = {
    enable = true;
    capSysNice = true;
    package = pkgs.unstable.gamescope;
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
    gnupg
    google-chrome
    gtk3
    haveged
    htop
    imagemagick
    inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
    iotop
    jdk17
    jq
    just
    kbfs
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
    mesa-demos
    ncdu
    nh
    nix-fast-build
    nix-tree
    nushell
    obsidian
    parted
    pinentry-gnome3
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
    };
  };

  services = {
    atd.enable = lib.mkDefault true;
    cpupower-gui.enable = false;
    haveged.enable = lib.mkDefault true;
    kbfs.enable = lib.mkDefault true;
    keybase.enable = lib.mkDefault true;

    avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = true;
      openFirewall = true;
    };

    flatpak = {
      enable = lib.mkDefault true;
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
      enable = lib.mkDefault true;
      drivers = [
        pkgs.brlaser
      ];
    };
  };

  systemd.services."flatpak-managed-install" = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
