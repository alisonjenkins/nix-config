{ lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    ../../app-profiles/desktop
    ../../app-profiles/desktop/kwallet
    ../../app-profiles/hardware/fingerprint-reader
    ../../app-profiles/hardware/touchpad
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  boot = {
    bootspec.enableValidation = true;
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    # kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    # kernelPackages = pkgs.linuxPackages_zen;
    kernelPackages = pkgs.linuxPackages_cachyos-lto;

    kernelParams = [
      # "mem_sleep_default=deep"
      "tc_cmos.use_acpi_alarm=1"
    ];

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
      "net.ipv4.tcp_mtu_probing" = lib.mkForce 1;
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

    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };

    loader = {
      efi.efiSysMountPoint = "/boot";
      # grub = {
      #   enable = true;
      #   devices = [ "nodev" ];
      #   efiInstallAsRemovable = true;
      #   efiSupport = true;
      #   useOSProber = true;
      #   # theme = pkgs.stdenv.mkDerivation {
      #   #   pname = "distro-grub-themes";
      #   #   version = "3.1";
      #   #   src = pkgs.fetchFromGitHub {
      #   #     owner = "AdisonCavani";
      #   #     repo = "distro-grub-themes";
      #   #     rev = "v3.1";
      #   #     hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
      #   #   };
      #   #   installPhase = "cp -r customize/nixos $out";
      #   # };
      # };
      systemd-boot.enable = lib.mkForce false;
    };
  };

  console.keyMap = "us";

  chaotic = {
    mesa-git = {
      enable = false;
      # method = "GBM_BACKENDS_PATH";
    };
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    persistence = {
      "/persistence" = {
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
            parentDirectory = { mode = "u=rwx,g=,o="; };
          }
        ];
      };
    };

    systemPackages = with pkgs; [
      deepfilternet
      easyeffects
      framework-tool
      ldacbt
      qmk
      qmk-udev-rules
      qmk_hid
      sbctl
      tpm2-tss
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware = {
    enableRedistributableFirmware = true;
    graphics.enable = true;
    keyboard.qmk.enable = true;
    pulseaudio.enable = false;
    wirelessRegulatoryDatabase = true;
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
    hostName = "ali-framework-laptop";
    extraHosts = ''
      192.168.1.202 home-kvm-hypervisor-1
    '';
    networkmanager.enable = true;
  };

  nix = {
    package = pkgs.nix;
    extraOptions = "experimental-features = nix-command flakes";

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
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.bacon-nextest
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
    zsh.enable = true;
  };

  security.rtkit.enable = true;

  services = {
    auto-cpufreq = {
      enable = false;

      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };

    fwupd = {
      enable = true;
    };

    logind = {
      lidSwitch = "suspend-then-hibernate";
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    power-profiles-daemon.enable = lib.mkForce true;

    thermald = {
      enable = true;
    };

    # udev = {
    # extraRules = ''
    #   SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", ATTR{power/wakeup}="disabled", ATTR{driver/1-1.1.1.4/power/wakeup}="disabled"
    #   SUBSYSTEM=="usb", DRIVERS=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0014", ATTR{power/wakeup}="disabled", ATTR{driver/1-1.1.1.4/power/wakeup}="disabled"
    # '';
    # };

    xserver = {
      videoDrivers = [
        "fbdev"
        "modesetting"
      ];
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };

  stylix =
    let
      wallpaper = pkgs.fetchurl {
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
      #   mode = "0400";
      #   sopsFile = ../../secrets/ali-framework-laptop/home-enc-key.enc.bin;
      #   owner = config.users.users.root.name;
      #   group = config.users.users.nobody.group;
      #   path = "/etc/luks/home.key";
      #   format = "binary";
      # };
    };
  };

  system = {
    stateVersion = "24.11";
  };

  systemd = {
    sleep = {
      extraConfig = ''
        HibernateDelaySec=30m
        SuspendState=mem
      '';
    };
  };

  time.timeZone = "Europe/London";

  users = {
    users = {
      ali = {
        autoSubUidGidRange = true;
        isNormalUser = true;
        description = "Alison Jenkins";
        extraGroups = [ "networkmanager" "wheel" "docker" ];
        hashedPasswordFile = "/persistence/passwords/ali";
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = false;
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

  zramSwap = {
    enable = true;
  };
}

