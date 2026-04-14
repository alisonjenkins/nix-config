# Hetzner Cloud configuration module
# Optimized for fast boot and minimal footprint on Hetzner Cloud instances.
# SSH is the primary access method (Hetzner has no SSM-like agent).
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.hetzner;
in
{
  options.modules.hetzner = {
    enable = lib.mkEnableOption "Hetzner Cloud configuration";

    enableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenSSH (enabled by default — Hetzner's primary access method)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Boot speed optimizations
    boot = {
      loader.timeout = lib.mkForce 0;

      initrd = {
        systemd.enable = true;
        includeDefaultModules = false;
        kernelModules = [ "virtio_blk" "virtio_pci" "virtio_net" ];
      };

      kernelParams = [
        "quiet"
        "rd.systemd.show_status=false"
        "systemd.show_status=false"
        "console=tty0"
        "console=ttyS0,115200" # Hetzner serial console
      ];

      # Network performance tuning
      kernel.sysctl = {
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_fastopen" = 3;
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
        "net.ipv4.tcp_wmem" = "4096 1048576 16777216";
        "net.core.netdev_max_backlog" = 16384;

        # inotify limits for k8s/k3s workloads
        "fs.inotify.max_user_instances" = 1024;
        "fs.inotify.max_user_watches" = 524288;
        "fs.inotify.max_queued_events" = 65536;
      };
    };

    # Root filesystem tuning — reduce write I/O
    fileSystems."/" = lib.mkDefault {
      options = [ "noatime" "lazytime" "commit=60" ];
    };

    # Cloud-init for Hetzner instance provisioning
    services.cloud-init = {
      enable = true;
      network.enable = false; # systemd-networkd handles networking

      settings = {
        datasource_list = [ "Hetzner" ];

        cloud_init_modules = [
          "seed_random"
          "growpart"
          "resizefs"
          "update_hostname"
          "users-groups"
          "ssh"
        ];

        cloud_config_modules = [
          "ssh-import-id"
          "set-passwords"
          "runcmd"
        ];

        cloud_final_modules = [
          "scripts-per-once"
          "scripts-per-boot"
          "scripts-per-instance"
          "scripts-user"
          "final-message"
        ];
      };
    };

    # Strip documentation from closure
    documentation.enable = false;

    # Strip desktop packages from closure
    xdg.icons.enable = false;
    xdg.mime.enable = false;
    xdg.sounds.enable = false;
    fonts.fontconfig.enable = false;
    programs.command-not-found.enable = false;
    environment.defaultPackages = lib.mkForce [];

    # Use tmpfs for /tmp
    boot.tmp.useTmpfs = true;

    # Network: use systemd-networkd for faster DHCP
    networking = {
      useNetworkd = true;
      useDHCP = false;

      firewall = {
        enable = true;
        allowedTCPPorts = lib.optionals cfg.enableSSH [ 22 ];
      };
    };

    systemd.network = {
      enable = true;
      wait-online.enable = false;

      # Hetzner uses en* for virtio-net interfaces
      networks."10-hetzner" = {
        matchConfig.Name = "en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
      };
    };

    # SSH: enabled by default on Hetzner (primary access method)
    services.openssh = {
      enable = cfg.enableSSH;
      settings = lib.mkIf cfg.enableSSH {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = lib.mkForce "no";
      };
    };

    # Minimal packages
    environment.systemPackages = with pkgs; [
      cloud-utils.guest  # growpart for cloud-init
      curl
      e2fsprogs          # resize2fs for cloud-init
      htop
      jq
      vim
    ];

    # Nix settings
    nix = {
      extraOptions = "experimental-features = nix-command flakes";

      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };

      settings = {
        auto-optimise-store = true;
        trusted-users = [ "root" "@wheel" ];
      };
    };

    nixpkgs.config.allowUnfree = true;

    # Use public NTP servers (Hetzner has no proprietary time service)
    services.timesyncd = {
      enable = true;
      servers = [
        "ntp1.hetzner.de"
        "ntp2.hetzner.com"
        "ntp3.hetzner.net"
      ];
    };

    # zram swap — compressed swap in RAM
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 100;
    };

    # Cap journal size
    services.journald.extraConfig = "SystemMaxUse=50M";

    # Disable unnecessary services
    services.fwupd.enable = false;
    systemd.services.systemd-journal-catalog-update.enable = false;
    systemd.services.systemd-update-utmp.enable = false;
  };
}
