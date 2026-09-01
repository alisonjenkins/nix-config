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

    networking.nftables.enable = true;

    # SSDP (UPnP discovery): a router's reply to a multicast M-SEARCH arrives
    # as unicast from a different source address than the multicast
    # destination the request was sent to, so conntrack never marks it
    # "related" — it lands on our ephemeral src port, not 1900, so
    # allowedUDPPorts (which only matches dest port) can't allow it. Allow by
    # the reply's source port instead, restricted to ephemeral destination
    # ports (SSDP client sockets don't bind low/privileged ports) so this
    # can't be used to bypass the firewall for a well-known service port.
    # Not scoped to a LAN subnet since these are laptops that roam networks.
    networking.firewall.extraInputRules = ''
      udp sport 1900 udp dport 1024-65535 accept comment "SSDP (UPnP discovery) replies"
    '';

    # `sudo -A` (e.g. from an agent's shell tool with no controlling tty)
    # uses this askpass helper, which pops a GUI password prompt instead of
    # failing outright.
    environment.sessionVariables.SUDO_ASKPASS = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

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
      kdePackages.ksshaskpass
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
      libxscrnsaver
      libxcursor
      libxi
      libxinerama
      yazi
      zsh
    ]
    # x86_64-only packages — discord/wine/google-chrome/kbfs/
    # keybase-gui/zoom-us upstream don't ship aarch64 builds. Gate so
    # the module is reusable on Asahi.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 (with pkgs; [
      discord
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

      # avahi (above) is the mDNS responder here; without this,
      # systemd-resolved runs its own mDNS responder in parallel and both
      # answer the same queries — "Detected another IPv4 mDNS stack running
      # on this host" in the avahi-daemon log, and unreliable .local lookups.
      resolved.settings.Resolve.MulticastDNS = lib.mkDefault "no";

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
          # Deliberately NOT on activation: NetworkManager and
          # systemd-resolved are themselves restarted during a switch, so
          # flathub is intermittently unresolvable exactly while this unit
          # runs. A failed flatpak install then fails switch-to-configuration,
          # which makes deploy-rs roll the whole deployment back. The unit
          # still runs at boot and on the daily timer below.
          onActivation = false;
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
      # network-online.target alone is not enough during a switch: it is already
      # reached, so the unit starts while systemd-resolved is still restarting
      # and flathub fails to resolve, which fails the whole activation.
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "systemd-resolved.service"
        "nss-lookup.target"
      ];
    };
  };
}
