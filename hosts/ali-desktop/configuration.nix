{ config
, inputs
, outputs
, pkgs
, lib
, ...
}: {
  imports = [
    # inputs.nix-gaming.nixosModules.pipewireLowLatency
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
      inherit inputs lib;
    })
    (import ../../modules/locale { })
    ../../app-profiles/desktop
    ./hardware-configuration.nix
  ];

  boot = {
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    # kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    kernelPackages = pkgs.linuxPackages_cachyos-lto;

    binfmt = {
      emulatedSystems = [ "aarch64-linux" ];
    };

    extraModprobeConfig = ''
      options v4l2loopback exclusive_caps=1,1,1 video_nr=1,2,3 card_label="Virtual Video Output 1","Virtual Video Output 2","Virtual Video Output 3"
    '';

    kernelParams = [
      "amdgpu.ppfeaturemask=0xfff7ffff"
      "quiet"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    kernelModules = [
      "sg"
      "v4l2loopback"
    ];
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    etc = {
      "crypttab".text = ''
        # <name>       <device>                                     <password>              <options>
        home1          UUID=ee7395ed-e76a-4179-8e92-42e35250e98d    /etc/luks/home.key
        home2          UUID=1ac3af7c-5af5-4972-b4b6-0245cc072a65    /etc/luks/home.key
      '';
    };

    systemPackages = with pkgs; [
      # handbrake
      # libsForQt5.polonium
      # makemkv
      # stable.ananicy-cpp-rules
      alsa-scarlett-gui
      amdgpu_top
      cpu-x
      deadd-notification-center
      geekbench
      i2pd
      innoextract
      kdePackages.korganizer
      lact
      libaacs
      openrct2
      openttd
      openttd-ttf
      polkit
      protontricks
      qbittorrent
      radeontop
      s-tui
      stable.ananicy-cpp
      stress
      sweethome3d.application
      sweethome3d.furniture-editor
      sweethome3d.textures-editor
      sysbench
      uhk-agent
      upscayl
      webcamoid
      wireguard-tools
      xd
      yt-dlp
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
      PATH = [ "\${HOME}/.local/bin" "\${HOME}/.config/rofi/scripts" ];
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware = {
    cpu = {
      amd = {
        updateMicrocode = true;
      };
    };

    graphics = {
      enable = true;
    };
  };

  musnix = {
    enable = true;
  };

  networking = {
    hostName = "ali-desktop";

    nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];
  };

  nixpkgs = {
    overlays = [
      # outputs.overlays.alvr
      # outputs.overlays.ffmpeg
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays._7zz
      outputs.overlays.additions
      outputs.overlays.bacon-nextest
      outputs.overlays.bluray-playback
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.python3PackagesOverlay
      outputs.overlays.qtwebengine
      outputs.overlays.quirc
      outputs.overlays.snapper
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
      outputs.overlays.unstable-packages
    ];

    config = {
      allowUnfree = true;
      permittedInsecurePackages = [ ];
    };
  };

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = "experimental-features = nix-command flakes";
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      auto-optimise-store = false;
      trusted-users = [ "root" "@wheel" ];

      substituters = [
        "https://cosmic.cachix.org/"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };
  };

  powerManagement = {
    cpuFreqGovernor = "performance";
  };

  programs = {
    envision = {
      enable = true;
      openFirewall = true;
    };

    java = {
      enable = true;
      package = pkgs.jdk17;
    };

    river = {
      enable = true;
    };

    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      package = pkgs.steam.override {
        extraEnv = { };
        extraLibraries = pkgs:
          with pkgs; [
            xorg.libXcursor
            xorg.libXi
            xorg.libXinerama
            xorg.libXScrnSaver
            libpng
            libpulseaudio
            libvorbis
            stdenv.cc.cc.lib
            libkrb5
            keyutils
          ];
      };
      gamescopeSession = {
        enable = false;
        args = [
          "--rt"
          "-f"
          "-o 10"
        ];
      };
    };
  };

  services = {
    # beesd = {
    #   filesystems = {
    #     persistence = {
    #       extraOptions = ["--loadavg-target" "5.0"];
    #       hashTableSizeMB = 2048;
    #       spec = "LABEL=persistence";
    #       verbosity = "crit";
    #     };
    #   };
    # };

    btrfs = {
      autoScrub = {
        enable = true;
        fileSystems = [
          "/persistence"
        ];
      };
    };

    desktopManager = {
      cosmic = {
        enable = true;
      };
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      jack.enable = true;
      pulse.enable = true;
      systemWide = false;

      # lowLatency = {
      #   enable = true;
      #   quantum = 4;
      #   rate = 48000;
      # };
    };

    udev = {
      extraRules = ''
        SUBSYSTEM=="pci", DRIVER=="amdgpu", ATTR{power_dpm_force_performance_level}="low"
      '';

      packages = [
        pkgs.uhk-udev-rules
      ];
    };

    snapper = {
      persistentTimer = true;
      configs = {
        nix = {
          SUBVOLUME = "/nix";
          ALLOW_USERS = [ "ali" ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
        };

        persistence = {
          SUBVOLUME = "/persistence";
          ALLOW_USERS = [ "ali" ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
        };
      };
    };

    system76-scheduler = {
      enable = true;
      settings = {
        processScheduler = {
          pipewireBoost = {
            enable = true;
            profile = {
              ioClass = "realtime";
              class = "fifo";
              prio = "80";
            };
          };
        };
      };
    };

    wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = true;
      autoStart = true;
      config = {
        enable = true;

        json = {
          # 1.0x foveation scaling
          scale = 1.0;
          # 100 Mb/s
          bitrate = 100000000;
          encoders = [
            {
              encoder = "vaapi";
              codec = "h265";
              # 1.0 x 1.0 scaling
              width = 1.0;
              height = 1.0;
              offset_x = 0.0;
              offset_y = 0.0;
            }
          ];
        };
      };
    };

    xserver = {
      videoDrivers = [ "amdgpu" ];
      xkb.layout = "us";
      xkb.variant = "";
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/main.enc.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      # "myservice/my_subdir/my_secret" = {
      #   mode = "0400";
      #   owner = config.users.users.nobody.name;
      #   group = config.users.users.nobody.group;
      #   restartUnits = ["example.service"];
      #   path = "/a/secret/path.yaml";
      #   format = "yaml"; # can be yaml, json, ini, dotenv, binary
      # };
      home_enc_key = {
        format = "binary";
        group = config.users.users.nobody.group;
        mode = "0400";
        neededForUsers = true;
        owner = config.users.users.root.name;
        path = "/etc/luks/home.key";
        sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
      };
    };
  };

  stylix =
    let
      wallpaper = pkgs.fetchurl
        {
          url = "https://raw.githubusercontent.com/alisonjenkins/nix-config/refs/heads/main/home/wallpapers/5120x1440/Static/sakura.jpg";
          hash = "sha256-rosIVRieazPxN7xrpH1HBcbQWA/1FYk1gRn1vy6Xe3s=";
        };
    in
    {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
      enable = true;
      image = wallpaper;
      polarity = "dark";

      cursor = {
        package = pkgs.material-cursors;
        name = "material_light_cursors";
      };

      fonts = {
        serif = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        sansSerif = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        monospace = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        emoji = {
          package = pkgs.noto-fonts-emoji;
          name = "Noto Color Emoji";
        };
      };

      opacity = {
        desktop = 0.0;
        terminal = 0.9;
      };

      targets = {
        nixvim = {
          transparentBackground = {
            main = true;
            signColumn = true;
          };
        };
      };
    };

  system = {
    stateVersion = "24.05";
  };

  systemd = {
    services = {
      lact = {
        description = "AMDGPU Control Daemon";
        after = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.lact}/bin/lact daemon";
        };
        enable = true;
      };
    };
  };

  users = {
    defaultUserShell = pkgs.zsh;
    mutableUsers = false;

    users = {
      ali = {
        autoSubUidGidRange = true;
        description = "Alison Jenkins";
        extraGroups = [ "audio" "docker" "networkmanager" "pipewire" "wheel" ];
        isNormalUser = true;
        hashedPasswordFile = "/persistence/passwords/ali";
        useDefaultShell = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = true;
    };

    libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
      qemu.ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
