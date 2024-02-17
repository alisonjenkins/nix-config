{ lib, pkgs, inputs, system, ... }:
{
  boot = {
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
      ];
    };
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      theme = "breeze";
    };
    kernelParams = [ "quiet" ];
  };

  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  services.xserver.deviceSection = ''
    Option "DRI" "3"
  '';

  environment.systemPackages = with pkgs;
    [
      # gamescope
      # inputs.jovian-nixos.legacyPackages.${system}.gamescope
      # mangohud32_git
      # mangohud_git
      age
      arrpc
      bat
      bc
      beancount
      cachix
      cargo
      chromium
      colmena
      comma
      corectrl
      crunchy-cli
      dig
      discord
      droidcam
      ethtool
      fava
      fd
      ffmpeg
      fzf
      gamemode
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
      inputs.jovian-nixos.legacyPackages.${system}.mangohud
      inputs.nh.packages.${system}.default
      inputs.nixpkgs_master.legacyPackages.${system}.alvr
      iotop
      jdk17
      just
      kbfs
      keybase
      keybase-gui
      keyutils
      kodi-cli
      kodi-wayland
      libkrb5
      libpng
      libpulseaudio
      libreoffice
      libvorbis
      lshw
      luxtorpeda
      mesa32_git
      mesa_git
      mpv-vapoursynth
      ncdu
      nnn
      nushellFull
      obsidian
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
      vmtouch
      vulkan-tools
      vulnix
      wine
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
        "dev.vencord.Vesktop"
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
      drivers = [
        pkgs.brlaser
      ];
    };
  };
}
