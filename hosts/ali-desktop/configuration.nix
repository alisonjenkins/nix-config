{
  config,
  inputs,
  lib,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    ../../app-profiles/desktop
    ./hardware-configuration.nix
    # inputs.nix-gaming.nixosModules.pipewireLowLatency
  ];

  console.keyMap = "us";
  hardware.pulseaudio.enable = false;
  programs.zsh.enable = true;
  time.timeZone = "Europe/London";

  boot = {
    consoleLogLevel = 0;
    initrd.verbose = false;
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    kernelParams = [
      "quiet"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    kernelModules = [
      "sg"
      # "v4l2loopback"
    ];
    # extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];

    # extraModprobeConfig = ''
    #   options v4l2loopback exclusive_caps=1,1,1 video_nr=1,2,3 card_label="Virtual Video Output 1","Virtual Video Output 2","Virtual Video Output 3"
    # '';

    kernel.sysctl = {
      # Network Perf Tuning
      "net.core.netdev_max_backlog" = 16384;
      # "net.core.netdev_budget" = 50000;
      # "net.core.netdev_budget_usecs" = 5000;
      "net.core.default_qdisc" = "cake";
      "net.core.optmem_max" = 65536;
      "net.core.rmem_default" = 1048576;
      "net.core.rmem_max" = 16777216;
      "net.core.somaxconn" = 8192;
      "net.core.wmem_default" = 1048576;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.default.log_martians" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv4.icmp_echo_ignore_all" = 1;
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_fin_timeout" = 10;
      "net.ipv4.tcp_keepalive_intvl" = 10;
      "net.ipv4.tcp_keepalive_probes" = 6;
      "net.ipv4.tcp_keepalive_time" = 60;
      "net.ipv4.tcp_max_syn_backlog" = 8192;
      "net.ipv4.tcp_max_tw_buckets" = 2000000;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_rfc1337" = 1;
      "net.ipv4.tcp_rmem" = "4096 1048576 2097152";
      "net.ipv4.tcp_sack" = 1;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.tcp_timestamps" = 0;
      "net.ipv4.tcp_tw_reuse" = 1;
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      "net.ipv4.udp_rmem_min" = 8192;
      "net.ipv4.udp_wmem_min" = 8192;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.net.ipv4.tcp_window_scaling" = 1;

      # Virtual memory tuning
      "vm.swappiness" = lib.mkForce 10;
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 3;
      "vm.vfs_cache_pressure" = 50;
    };

    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      systemd-boot = {
        enable = true;
        consoleMode = "auto";
        memtest86.enable = true;
        netbootxyz.enable = true;
      };
    };
  };

  chaotic = {
    mesa-git = {
      enable = false;
      # method = "GBM_BACKENDS_PATH";
    };
    scx = {
      enable = false;
      scheduler = "scx_rustland";
    };
  };

  environment = {
    pathsToLink = ["/share/zsh"];

    etc = {
      "crypttab".text = ''
        # <name>       <device>                                     <password>              <options>
        home1          UUID=ee7395ed-e76a-4179-8e92-42e35250e98d    /etc/luks/home.key
        home2          UUID=1ac3af7c-5af5-4972-b4b6-0245cc072a65    /etc/luks/home.key
      '';
    };

    persistence = {
      "/persistence" = {
        hideMounts = true;
        directories = [
          "/etc/NetworkManager/system-connections"
          "/etc/luks"
          "/etc/ssh"
          "/var/lib/bluetooth"
          "/var/lib/flatpak"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
          "/var/log"
          {
            directory = "/var/lib/colord";
            user = "colord";
            group = "colord";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/var/cache/tuigreet";
            user = "greetd";
            group = "greetd";
            mode = "u=rwx,g=rx,o=";
          }
        ];
        files = [
          "/etc/machine-id"
          {
            file = "/var/keys/secret_file";
            parentDirectory = {mode = "u=rwx,g=,o=";};
          }
        ];
      };
    };

    systemPackages = with pkgs; [
      amdgpu_top
      ananicy-cpp-rules
      cpu-x
      geekbench
      handbrake
      i2pd
      kdePackages.korganizer
      lact
      libaacs
      libsForQt5.polonium
      makemkv
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
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
      PATH = ["\${HOME}/.local/bin" "\${HOME}/.config/rofi/scripts"];
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware.graphics = {
    enable = true;
  };

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  musnix = {
    enable = true;
  };

  networking = {
    enableIPv6 = false;
    hostName = "ali-desktop";
    interfaces.enp16s0.mtu = 9000;
    networkmanager.enable = true;

    extraHosts = ''
      192.168.1.202 home-kvm-hypervisor-1
    '';

    firewall.allowedTCPPorts = [
      25565
    ];

    nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];
  };

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      # outputs.overlays.alvr
      outputs.overlays.bluray-playback
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionx
      outputs.overlays.quirc
    ];

    config = {
      allowUnfree = true;
      permittedInsecurePackages = [];
    };
  };

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = "experimental-features = nix-command flakes";

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      auto-optimise-store = true;
      trusted-users = ["root" "@wheel"];
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

    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      package = pkgs.steam.override {
        extraEnv = {};
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
        enable = true;
        args = [
          "--rt"
          "-f"
          "-o 10"
        ];
      };
    };
  };

  security = {
    rtkit.enable = true;

    sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };

  services = {
    fstrim.enable = true;
    irqbalance.enable = true;
    resolved.enable = true;

    beesd = {
      filesystems = {
        persistence = {
          extraOptions = ["--loadavg-target" "5.0"];
          hashTableSizeMB = 2048;
          spec = "LABEL=persistence";
          verbosity = "crit";
        };
      };
    };

    btrfs = {
      autoScrub = {
        enable = true;
        fileSystems = [
          "/persistence"
        ];
      };
    };

    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
      settings.KbdInteractiveAuthentication = false;
      settings.PermitRootLogin = "no";
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

    udev.packages = [
      pkgs.uhk-udev-rules
    ];
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

    xserver = {
      videoDrivers = ["amdgpu"];
      xkb.layout = "us";
      xkb.variant = "";
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/main.enc.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
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
        mode = "0400";
        sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
        owner = config.users.users.root.name;
        group = config.users.users.nobody.group;
        path = "/etc/luks/home.key";
        format = "binary";
      };
    };
  };

  system = {
    autoUpgrade = {
      enable = true;
      flake = inputs.self.outPath;
      flags = [
        "--update-input"
        "nixpkgs"
        "-L"
      ];
      dates = "17:30";
    };
    stateVersion = "23.11";
  };

  users = {
    defaultUserShell = pkgs.zsh;
    mutableUsers = false;

    users = {
      ali = {
        autoSubUidGidRange = true;
        description = "Alison Jenkins";
        extraGroups = ["audio" "docker" "networkmanager" "pipewire" "wheel"];
        isNormalUser = true;
        hashedPasswordFile = "/persistence/passwords/ali";
        useDefaultShell = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
