# AWS/EC2 configuration module
# Optimized for fast boot and minimal footprint on EC2 instances.
# SSM agent (from amazon-image.nix) is the primary access method; SSH is opt-in.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.aws;
in
{
  options.modules.aws = {
    enable = lib.mkEnableOption "AWS/EC2 configuration";

    enableSSH = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenSSH (disabled by default, SSM agent is primary access)";
    };

    rootVolumeSize = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "auto" ]) lib.types.int;
      default = "auto";
      description = "Root volume size in GiB, or \"auto\" to fit the closure with minimal headroom. The partition auto-grows to the EBS volume size at boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Image size — applied to the amazon image builder via extendModules.
    # "auto" lets make-disk-image size the image to fit the closure;
    # the partition grows to the EBS volume at boot via growPartition.
    image.modules.amazon = lib.mkIf (cfg.rootVolumeSize != "auto") {
      virtualisation.diskSize = cfg.rootVolumeSize * 1024;
    };

    # Boot speed optimizations
    boot = {
      loader.timeout = lib.mkForce 0;

      initrd = {
        systemd.enable = true;
        includeDefaultModules = false;
        kernelModules = [ "nvme" ];
      };

      kernelParams = [
        "quiet"
        "rd.systemd.show_status=false"
        "systemd.show_status=false"
      ];

      # Network performance tuning
      kernel.sysctl = {
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_fastopen" = 3;
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
        "net.ipv4.tcp_wmem" = "4096 65536 16777216";
        "net.core.netdev_max_backlog" = 16384;
      };
    };

    # Root filesystem tuning — reduce write I/O during boot when NixOS
    # reads hundreds of store paths. Safe for immutable infrastructure
    # where runtime state lives in EBS snapshots / S3 / external DBs.
    fileSystems."/" = lib.mkDefault {
      options = [ "noatime" "lazytime" "commit=60" "data=writeback" ];
    };

    # Disable amazon-init (pre-baked AMIs don't need nixos-rebuild on boot);
    # cloud-init handles instance provisioning instead.
    virtualisation.amazon-init.enable = false;

    # Cloud-init for EC2 instance provisioning (SSH keys, hostname, user-data scripts)
    services.cloud-init = {
      enable = true;
      network.enable = false; # We manage networking via systemd-networkd above

      settings = {
        datasource_list = [ "Ec2" ];
        datasource.Ec2.metadata_urls = [ "http://169.254.169.254" ];

        # Only run modules relevant to pre-baked AMIs
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

    # Strip documentation from closure — servers don't need man/info/manual
    documentation.enable = false;

    # Strip desktop packages from closure
    xdg.icons.enable = false;
    xdg.mime.enable = false;
    xdg.sounds.enable = false;
    fonts.fontconfig.enable = false;
    programs.command-not-found.enable = false;
    environment.defaultPackages = lib.mkForce [];

    # Use tmpfs for /tmp to avoid disk I/O for temp files
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

      networks."10-ec2" = {
        matchConfig.Name = "en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
      };
    };

    # SSH: opt-in only (mkForce overrides amazon-image.nix default of true)
    services.openssh = {
      enable = lib.mkForce cfg.enableSSH;
      settings = lib.mkIf cfg.enableSSH {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = lib.mkForce "no";
      };
    };

    # Minimal packages — awscli2 excluded to save ~400 MiB of closure;
    # install on-demand via `nix run nixpkgs#awscli2` or user profile.
    environment.systemPackages = with pkgs; [
      cloud-utils.guest  # growpart — required by cloud-init growpart module to expand partitions
      curl
      e2fsprogs          # resize2fs — required by cloud-init resizefs module to grow ext4 filesystems
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

    # Use Amazon Time Sync Service
    services.timesyncd = {
      enable = true;
      servers = [ "169.254.169.123" ];
    };

    # zram swap — compressed swap in RAM to handle memory spikes during
    # heavy builds (kernel LTO linking, rocblas, etc.) without disk I/O
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 100;
    };

    # Cap journal size to reduce I/O from rotation
    services.journald.extraConfig = "SystemMaxUse=50M";

    # Disable unnecessary services
    services.fwupd.enable = false;

    systemd.services.systemd-journal-catalog-update.enable = false;
    systemd.services.systemd-update-utmp.enable = false;
  };
}
