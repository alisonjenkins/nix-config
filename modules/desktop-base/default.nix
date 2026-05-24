{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.desktop-base;
in
{
  options.modules.desktop-base = {
    enable = lib.mkEnableOption "base desktop environment packages and services";
  };

  config = lib.mkIf cfg.enable {
    modules.base.useAliNeovim = true;

    # gamescope pulls 32-bit graphics (pkgsi686Linux) into hardware.graphics
    # — x86-only. Skip on aarch64; arm gaming via FEX has its own path
    # (see modules/desktop-gaming-arm64).
    programs.gamescope = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
      enable = true;
      capSysNice = true;
      package = pkgs.unstable.gamescope;
    };

    services.xserver.deviceSection = ''
      Option "DRI" "3"
    '';

    environment.systemPackages = with pkgs; [
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
      gtk3
      haveged
      htop
      imagemagick
      inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
      iotop
      jdk17
      jq
      just
      keybase
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
      xdg-utils
      xorg.libXScrnSaver
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      yazi
      zsh
    ]
    # x86_64-only packages — discord-canary/wine/google-chrome/kbfs/
    # keybase-gui/zoom-us upstream don't ship aarch64 builds. Gate so
    # the module is reusable on Asahi.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (with pkgs; [
      discord-canary
      google-chrome
      kbfs
      keybase-gui
      wine
      zoom-us
    ]);

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
      # keybase + kbfs binaries are x86-only on Linux.
      kbfs.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
      keybase.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;

      avahi = {
        enable = lib.mkDefault true;
        nssmdns4 = true;
        openFirewall = true;
      };

      flatpak = {
        enable = lib.mkDefault true;
        # Nyrna and Sober only publish x86_64 builds on flathub. On aarch64
        # the managed-install service retries forever with
        # "Nothing matches <app> in remote flathub". Gate them by arch.
        packages = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
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
  };
}
