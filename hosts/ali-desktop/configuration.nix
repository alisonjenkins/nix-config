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
    (import ../../modules/desktop {
      inherit inputs pkgs lib;
    })
    (import ../../modules/locale { })
    (import ../../modules/vr { enableOpenSourceVR = false; })
    (import ../../modules/ollama)
    (import ../../modules/rocm { inherit pkgs; })
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

    kernelPatches = [
      {
        name = "amdgpu-ignore-ctx-privileges";
        patch = pkgs.fetchpatch {
          name = "cap_sys_nice_begone.patch";
          url = "https://github.com/Frogging-Family/community-patches/raw/master/linux61-tkg/cap_sys_nice_begone.mypatch";
          hash = "sha256-Y3a0+x2xvHsfLax/uwycdJf3xLxvVfkfDVqjkxNaYEo=";
        };
      }
    ];

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
      # libsForQt5.polonium
      # stable.ananicy-cpp-rules
      # system-bridge
      alsa-scarlett-gui
      amdgpu_top
      cpu-x
      deadd-notification-center
      geekbench
      handbrake
      i2pd
      innoextract
      kdePackages.korganizer
      lact
      libaacs
      lsscsi
      mkvtoolnix
      moonlight-qt
      openrct2
      openttd
      openttd-ttf
      podman
      polkit
      protontricks
      qbittorrent
      radeontop
      s-tui
      stable.ananicy-cpp
      stress
      sunshine
      sweethome3d.application
      sweethome3d.furniture-editor
      sweethome3d.textures-editor
      sysbench
      uhk-agent
      unstable.makemkv
      upscayl
      webcamoid
      wireguard-tools
      xd
      yt-dlp
      zk

      (kodi.withPackages (pkgs: with pkgs; [
        kodiPackages.a4ksubtitles
        kodiPackages.inputstream-rtmp
        kodiPackages.inputstreamhelper
        kodiPackages.invidious
        kodiPackages.jellyfin
        kodiPackages.joystick
        kodiPackages.netflix
        kodiPackages.plugin-cache
        kodiPackages.requests-cache
        kodiPackages.sendtokodi
        kodiPackages.sponsorblock
        kodiPackages.upnext
        kodiPackages.visualization-fishbmc
        kodiPackages.visualization-goom
        kodiPackages.visualization-matrix
        kodiPackages.visualization-pictureit
        kodiPackages.visualization-projectm
        kodiPackages.visualization-shadertoy
        kodiPackages.visualization-spectrum
        kodiPackages.visualization-starburst
        kodiPackages.visualization-waveform
      ]))
    ];

    variables = {
      PATH = [ "\${HOME}/.local/bin" "\${HOME}/.config/rofi/scripts" ];
    };
  };

  hardware = {
    cpu = {
      amd = {
        updateMicrocode = true;
      };
    };
  };

  networking = {
    hostName = "ali-desktop";

    firewall = {
      allowedTCPPorts = [
        29087
      ];
    };

    nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];

    interfaces = {
      "enp16s0" = {
        wakeOnLan = {
          enable = true;
        };
      };
    };
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
    java = {
      enable = true;
      package = pkgs.jdk17;
    };

    river = {
      enable = true;
    };
  };

  # security = {
  #   wrappers = {
  #     sunshine = {
  #       owner = "root";
  #       group = "root";
  #       capabilities = "cap_sys_admin+p";
  #       source = "${pkgs.sunshine}/bin/sunshine";
  #     };
  #   };
  # };

  services = {
    avahi = {
      publish = {
        enable = true;
        userServices = true;
      };
    };

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

    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      package = pkgs.unstable.sunshine;
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
      # home_enc_key = {
      #   format = "binary";
      #   group = config.users.users.nobody.group;
      #   mode = "0400";
      #   neededForUsers = true;
      #   owner = config.users.users.root.name;
      #   path = "/etc/luks/home.key";
      #   sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
      # };
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
    tmpfiles = {
      rules = [ "d /var/cache/jellyfin 1770 jellyfin jellyfin -" ];
    };
  };

  users = {
    defaultUserShell = pkgs.zsh;
    mutableUsers = false;

    groups = {
      jellyfin = {
        gid = 1000;
      };
    };

    users = {
      ali = {
        autoSubUidGidRange = true;
        description = "Alison Jenkins";
        isNormalUser = true;
        hashedPasswordFile = "/persistence/passwords/ali";
        useDefaultShell = true;

        extraGroups = [
          "audio"
          "cdrom"
          "docker"
          "jellyfin"
          "networkmanager"
          "pipewire"
          "video"
          "wheel"
        ];
      };
      jellyfin = {
        isNormalUser = false;
        isSystemUser = true;
        uid = 1001;
        group = "jellyfin";
        home = "/home/jellyfin";
        createHome = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    # docker = {
    #   enable = true;
    # };

    podman = {
      autoPrune.enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
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

    oci-containers = {
      containers = {
        jellyfin = {
          autoStart = true;
          # pull = "always";
          image = "docker.io/jellyfin/jellyfin:latest";
          serviceName = "jellyfin";
          user = "1001:1000";

          environment = {
            HEALTHCHECK_URL = "http://localhost:29087/health";
          };

          extraOptions = [
            # "--device /dev/dri:/dev/dri"
            "--network=host"
          ];

          labels = {
            "io.containers.autoupdate" = "registry";
          };

          ports = [
            "0.0.0.0:29087:29087"
          ];

          volumes = [
            "/var/cache/jellyfin:/cache"
            "/home/jellyfin/config:/config"
            "/media/storage1/Media:/media"
          ];
        };
      };
    };
  };
}
