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

      kernelParams = [ "quiet" ];

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

    # Disable amazon-init (pre-baked AMIs don't need nixos-rebuild on boot)
    virtualisation.amazon-init.enable = false;

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

    # Minimal packages
    environment.systemPackages = with pkgs; [
      awscli2
      curl
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

    # Disable unnecessary services
    services.fwupd.enable = false;
  };
}
