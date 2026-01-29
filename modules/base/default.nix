{ consoleKeyMap ? "us"
, enableIPv6 ? false
, enableImpermanence ? false
, enableOpenSSH ? true
, enablePlymouth ? true
, impermanencePersistencePath ? builtins.toPath "/persistence"
, beesdFilesystems ? {}
, inputs
, lib
, outputs
, pkgs
, timezone ? "Europe/London"
, useAliNeovim ? false
, useGrub ? false
, useSecureBoot ? false
, pcr15Value ? null
, useSystemdBoot ? true
, ...
}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote
    ./vm-variant.nix
  ] ++ lib.optional (builtins.pathExists /etc/nixos/cachix/ajenkins-public.nix) [ /etc/nixos/cachix/ajenkins-public.nix ]
  ++ (if useSecureBoot then [
    ../luksPCR15
  ] else []);

  config = lib.mkMerge [ {
  console.keyMap = consoleKeyMap;

  time.timeZone = timezone;

  boot = {
    consoleLogLevel = 0;
    kernelModules = [
      "sch_dualpi2"
    ];

    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
      ];
    };

    initrd = {
      verbose = false;

      # network = {
      #   enable = true;
      #
      #   ssh = {
      #     enable = true;
      #     port = 22;
      #     shell = "/bin/cryptsetup-askpass";
      #     authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      #     hostKeys = [ "/etc/ssh/keys/initrd/ssh_host_ed25519_key" ];
      #   };
      # };

      systemd = {
        enable = true;
      };
    };

    plymouth = {
      enable = enablePlymouth;
    };

    kernelParams = [
      "amdgpu.ppfeaturemask=0xfff7ffff"
      "preempt=full"
      "quiet"
    ];

    kernel = {
      sysctl = {
        "dev.hpet.max-user-freq" = 1000;
        "fs.dentry-negative" = 1;

        # Network Perf Tuning
        "net.core.default_qdisc" = "dualpi2";
        "net.core.netdev_max_backlog" = 16384;
        "net.core.optmem_max" = 65536;
        "net.core.rmem_default" = 1048576;
        "net.core.rmem_max" = 16777216;
        "net.core.somaxconn" = 8192;
        "net.core.wmem_default" = 1048576;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.all.log_martians" = 0;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.all.secure_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.default.log_martians" = 0;
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
        # "net.core.netdev_budget" = 50000;
        # "net.core.netdev_budget_usecs" = 5000;

        # Virtual memory tuning
        "vm.swappiness" = lib.mkDefault 10;
        "vm.dirty_ratio" = 20;              # Increased for better write caching (was 10)
        "vm.dirty_background_ratio" = 5;    # Increased for better background write caching (was 3)
        "vm.vfs_cache_pressure" = 25;       # Lower value = more aggressive disk caching (was 50)
      };
    };

    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

    } // (if useGrub then {
      grub = {
        devices = [ "nodev" ];
        efiInstallAsRemovable = false;
        efiSupport = true;
        enable = true;
        useOSProber = true;

        theme = pkgs.stdenv.mkDerivation {
          pname = "distro-grub-themes";
          version = "3.1";
          src = pkgs.fetchFromGitHub {
            owner = "AdisonCavani";
            repo = "distro-grub-themes";
            rev = "v3.1";
            hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
          };
          installPhase = "cp -r customize/nixos $out";
        };
      };
    } else {})
    // (if useSystemdBoot then {
      systemd-boot = {
        consoleMode = "auto";
        enable = true;
        memtest86.enable = true;
        netbootxyz.enable = true;
      };
    } else {});
  } // (if useSecureBoot then {
    loader.systemd-boot.enable = lib.mkForce false;

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
  } else {});

  environment = {
    systemPackages = with pkgs; [
      btop
      cachix
      dig
      git
      htop
      htop
      just
      lshw
      pciutils
      rush-parallel
      tmux
      unstable.tailscale
      vim
      yazi
    ] ++ (if useSecureBoot then [pkgs.sbctl] else [])
    ++ (if useAliNeovim then [
      inputs.ali-neovim.packages.${system}.nvim
    ] else [pkgs.neovim]);
  };

  networking = {
    enableIPv6 = enableIPv6;

    networkmanager = {
      enable = true;
    };
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
    };

    overlays = [
      inputs.nix-cachyos-kernel.overlays.pinned
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
      outputs.overlays.unstable-packages
    ];
  };

  nix = {
    extraOptions = "experimental-features = nix-command flakes";

    settings = {
      cores = 0;
      download-buffer-size = 268435456; # 256 MiB
      eval-cache = true;
      max-jobs = "auto";

      substituters = [
        "https://ajenkins-public.cachix.org"
        "https://attic.xuyh0120.win/lantian"
        "https://cache.garnix.io"
        "https://cache.nixos.org"
        "https://cosmic.cachix.org/"
        "https://hyprland.cachix.org"
        "https://jovian.cachix.org"
        "https://niri.cachix.org"
        "https://nix-community.cachix.org"
        "https://nixpkgs-wayland.cachix.org"
      ];

      trusted-public-keys = [
        "ajenkins-public.cachix.org-1:w/uYRGLft8KxQhPtQI1KPBy6j2eZRR8vLZjgLIKntzA="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "jovian.cachix.org-1:mAWLjAxLNI3RiPXtAE24VSpamW0gUfnGzroKvA/x2yE="
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      ];
    };
  };

  programs = {
    zsh = {
      enable = true;
    };
  };

  security = {
    rtkit.enable = true;

    pam = {
      loginLimits = [
        {
          domain = "@realtime";
          type = "-";
          item = "rtprio";
          value = 98;
        }
        {
          domain = "@realtime";
          type = "-";
          item = "memlock";
          value = "unlimited";
        }
        {
          domain = "@realtime";
          type = "-";
          item = "nice";
          value = -11;
        }
      ];
    };

    sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };

  services = {
    fstrim.enable = true;
    irqbalance.enable = true;
    pulseaudio.enable = false;
    resolved.enable = true;

    beesd = {
      filesystems = beesdFilesystems;
    };

    earlyoom = {
      enable = true;
    };

    fwupd = {
      enable = lib.mkDefault true;
    };

    openssh = {
      enable = enableOpenSSH;

      hostKeys = [
        {
          bits = 4096;
          path = "/persistence/etc/ssh/keys/ssh_host_rsa_key";
          type = "rsa";
        }
        {
          path = "/persistence/etc/ssh/keys/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
    };

    timesyncd = {
      enable = lib.mkDefault true;
    };

    udev = {
      extraRules = ''
        KERNEL=="cpu_dma_latency", GROUP="realtime"
      '';
    };
  };

  users = {
    users = {
      colord = {
        isSystemUser = true;
        group = "colord";
      };
    };
    groups = {
      colord = {};
      realtime = {};
    };
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # Optimal suspend and hibernate settings
  systemd.sleep = {
    extraConfig = ''
      # Hibernate settings - optimized for speed and SSD wear reduction
      # Use 'platform' mode for faster and more reliable hibernation on modern systems
      HibernateMode=platform

      # Suspend settings - use 'mem' (S3) for deeper sleep with better power savings
      # 'mem' is better than 's2idle' for battery life on most systems
      SuspendState=mem

      # Hybrid sleep settings - combines suspend and hibernate
      HybridSleepMode=platform
      HybridSleepState=disk

      # Allow up to 10 minutes for hibernation to complete (useful for large RAM)
      # Default is 3 minutes which may be too short for systems with 32GB+ RAM
      AllowHibernation=yes
      AllowSuspend=yes
      AllowHybridSleep=yes
      AllowSuspendThenHibernate=yes
    '';
  };

} (lib.mkIf enableImpermanence {
  environment = {
    persistence = {
      "${impermanencePersistencePath}" = {
        hideMounts = true;
        directories = [
          "/etc/NetworkManager/system-connections"
          "/etc/lact"
          "/etc/luks"
          "/var/lib/bluetooth"
          "/var/lib/flatpak"
          "/var/lib/fprint"
          "/var/lib/nixos"
          "/var/lib/power-profiles-daemon"
          "/var/lib/sddm"
          "/var/lib/systemd/coredump"
          "/var/log"
          {
            directory = "/var/lib/colord";
            user = "colord";
            group = "colord";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/var/lib/private";
            user = "root";
            group = "root";
            mode = "0700";
          }
          {
            directory = "/var/lib/samba";
            user = "root";
            group = "root";
            mode = "0700";
          }
          {
            directory = "/var/lib/tailscale";
            user = "root";
            group = "root";
            mode = "0700";
          }
          {
            directory = "/var/lib/private/ollama";
            user = "ollama";
            group = "ollama";
            mode = "0700";
          }
          {
            directory = "/var/cache/tuigreet";
            user = "greeter";
            group = "greeter";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/var/lib/regreet";
            user = "greeter";
            group = "greeter";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/etc/wireguard";
            user = "root";
            group = "root";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/etc/nixos/cachix";
            user = "root";
            group = "root";
            mode = "u=rwx,g=,o=";
          }
          {
            directory = "/var/lib/iwd";
            user = "root";
            group = "root";
            mode = "u=rwx,g=,o=";
          }
        ] ++ (if useSecureBoot then [
          {
            directory = "/var/lib/sbctl";
            group = "root";
            mode = "u=rwx,g=,o=";
            user = "root";
          }
        ] else []
        );
        files = [
          "/etc/machine-id"
          {
            file = "/var/keys/secret_file";
            parentDirectory = { mode = "u=rwx,g=,o="; };
          }
        ];
      };
    };
  };
})
(lib.mkIf useSecureBoot {
  systemIdentity = {
    enable = true;
    pcr15 = pcr15Value;
  };

}) ]; }
