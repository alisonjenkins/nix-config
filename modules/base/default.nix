{ consoleKeyMap ? "us"
, timezone ? "Europe/London"
, enableMesaGit ? false
, enablePlymouth ? true
, enableOpenSSH ? true
, enableIPv6 ? false
, enableImpermanence ? false
, imperpmanencePersistencePath ? builtins.toPath "/persistence"
, inputs
, lib
, ...
}: {
  imports = [
    inputs.chaotic.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
  ];
  console.keyMap = consoleKeyMap;
  hardware.pulseaudio.enable = false;
  time.timeZone = timezone;

  boot = {
    consoleLogLevel = 0;

    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
      ];
    };

    initrd = {
      verbose = false;

      systemd = {
        enable = true;
      };
    };

    plymouth = {
      enable = enablePlymouth;
    };

    kernelParams = [ "quiet" ];

    kernel = {
      sysctl = {
        "dev.hpet.max-user-freq" = 1000;
        "fs.dentry-negative" = 1;

        # Network Perf Tuning
        "net.core.default_qdisc" = "cake";
        "net.core.netdev_max_backlog" = 16384;
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
        # "net.core.netdev_budget" = 50000;
        # "net.core.netdev_budget_usecs" = 5000;

        # Virtual memory tuning
        "vm.swappiness" = lib.mkDefault 10;
        "vm.dirty_ratio" = 10;
        "vm.dirty_background_ratio" = 3;
        "vm.vfs_cache_pressure" = 50;
      };
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
      enable = enableMesaGit;
    };
  };

  networking = {
    enableIPv6 = enableIPv6;

    networkmanager = {
      enable = true;
    };
  };

  programs = {
    zsh = {
      enable = true;
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

    earlyoom = {
      enable = true;
      enableNotifications = true;
    };

    openssh = {
      enable = enableOpenSSH;

      hostKeys = [
        {
          bits = 4096;
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
        }
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  zramSwap = {
    enable = true;
  };
} // (if enableImpermanence then {
  environment = {
    persistence = {
      "${imperpmanencePersistencePath}" = {
        hideMounts = true;
        directories = [
          "/etc/NetworkManager/system-connections"
          "/etc/luks"
          "/etc/secureboot"
          "/etc/ssh"
          "/var/lib/bluetooth"
          "/var/lib/flatpak"
          "/var/lib/fprint"
          "/var/lib/nixos"
          "/var/lib/power-profiles-daemon"
          "/var/lib/sbctl"
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
            directory = "/var/lib/private/ollama";
            user = "ollama";
            group = "ollama";
            mode = "u=rwx,g=,o=";
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
        ];
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
} else { })
