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
    # Guard: Hetzner Cloud root disk is virtio-scsi; without these in the initrd
    # the root device never appears and the node drops to emergency mode [B5].
    assertions = [
      {
        assertion = builtins.elem "virtio_scsi" config.boot.initrd.kernelModules
          && builtins.elem "sd_mod" config.boot.initrd.kernelModules;
        message = "modules.hetzner: initrd must include virtio_scsi + sd_mod (Hetzner Cloud uses virtio-scsi /dev/sda) [B5].";
      }
    ];

    # Boot speed optimizations
    boot = {
      loader.timeout = lib.mkForce 0;

      initrd = {
        systemd.enable = true;
        includeDefaultModules = false;
        # Hetzner Cloud exposes the root disk over virtio-SCSI (/dev/sda), so the
        # initrd needs virtio_scsi + sd_mod or /dev/disk/by-label/nixos never
        # appears -> root timeout -> emergency mode [B5]. virtio_blk kept for
        # local virtio-blk testing.
        kernelModules = [ "virtio_blk" "virtio_scsi" "sd_mod" "virtio_pci" "virtio_net" ];
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

    # Cloud-init for Hetzner instance provisioning. cloud-init OWNS networking:
    # the Hetzner datasource renders networkd .network files for the public NIC
    # (v4 + v6) and each private network (matched by MAC). We must NOT also
    # hand-roll a systemd.network match for the same interface (races/clobbers).
    services.cloud-init = {
      enable = true;
      network.enable = true; # enables networkd; cloud-init writes the .network files

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
      wait-online.enable = false; # cloud-init configures the NIC post-boot
      # No static networks here — cloud-init (Hetzner datasource) is the SOLE
      # writer of .network files; a custom en* match would race it [B4].
    };

    # cloud-init-local must reach the metadata service (169.254.169.254) before
    # networking is up; without a DHCP client in PATH the metadata crawler fails
    # and no network config is ever written [B4, nixpkgs#215571].
    systemd.services.cloud-init-local.path = [ pkgs.dhcpcd ];
    systemd.services.systemd-networkd.stopIfChanged = false;
    systemd.services.systemd-resolved.stopIfChanged = false;

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

    # Cap journal size; persist to disk so early-boot failures survive a hang
    # (read /var/log/journal from rescue). Storage=persistent creates the dir.
    services.journald.extraConfig = ''
      SystemMaxUse=50M
      Storage=persistent
    '';

    # Disable unnecessary services
    services.fwupd.enable = false;
    systemd.services.systemd-journal-catalog-update.enable = false;
    systemd.services.systemd-update-utmp.enable = false;
  };
}
