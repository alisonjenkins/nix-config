{ inputs
, outputs
, lib
, pkgs
, username
, ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../app-profiles/desktop
    # ../../app-profiles/hardware/touchpad
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_cachyos;

    kernel = {
      sysctl = {
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
    };

    loader = {
      efi.efiSysMountPoint = "/boot";
      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiInstallAsRemovable = true;
        efiSupport = true;
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
    };
  };

  chaotic = {
    mesa-git = {
      enable = true;
    };
  };

  console.keyMap = "us";

  environment = {
    pathsToLink = [ "/share/zsh" ];

    variables = {
      NIXOS_OZONE_WL = "1";
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware = {
    graphics.enable = true;
    pulseaudio.enable = false;
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

  jovian = {
    devices.steamdeck.enable = true;

    steam = {
      enable = true;
      autoStart = true;
      user = username;
      desktopSession = "plasma";
    };
  };

  networking = {
    hostName = "ali-steam-deck";
    extraHosts = ''
      192.168.1.202 home-kvm-hypervisor-1
    '';
    networkmanager.enable = true;
  };

  nix = {
    package = pkgs.nixVersions.nix_2_22;
    extraOptions = "experimental-features = nix-command flakes";

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };
  };

  nixpkgs = {
    overlays = [
      inputs.nur.overlay
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.bacon-nextest
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
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
      pulse.enable = true;
    };

    xserver = {
      videoDrivers = [
        "fbdev"
        "intel"
        "modesetting"
      ];
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };

  system = {
    stateVersion = "24.05";
  };

  time.timeZone = "Europe/London";

  users = {
    users = {
      ali = {
        isNormalUser = true;
        description = "Alison Jenkins";
        initialPassword = "initPw!";
        extraGroups = [ "networkmanager" "wheel" "docker" ];
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
        packages = with pkgs; [
          firefox
          neofetch
          lolcat
        ];
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
