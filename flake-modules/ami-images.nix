{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Common module for all AMIs — UEFI boot for NitroTPM, Secure Boot, and
  # forward-compatibility with newer instance families.
  commonAmiModule = { ec2.efi = true; };

  # Shared AWS base server config (used by aws-base-server and aws-base-server-arm)
  awsBaseServerConfig = { modulesPath, lib, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws.enable = true;
    modules.locale.enable = true;

    modules.servers = {
      enable = true;
      openPrometheusFirewallPort = false;
    };

    networking.hostName = "aws-base-server";

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    system.stateVersion = "25.11";

    users.users.ali = {
      isNormalUser = true;
      description = "Alison Jenkins";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
      ];
    };
  };

  # Shared AWS K8s node config
  awsK8sNodeConfig = { modulesPath, lib, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws.enable = true;
    modules.locale.enable = true;

    modules.servers = {
      enable = true;
      openPrometheusFirewallPort = false;
    };

    networking.hostName = "aws-k8s-node";

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    system.stateVersion = "25.11";

    users.users.ali = {
      isNormalUser = true;
      description = "Alison Jenkins";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
      ];
    };
  };

  # Shared AWS nix builder config
  awsNixBuilderConfig = { modulesPath, lib, pkgs, inputs, ... }: {
    imports = [
      (modulesPath + "/virtualisation/amazon-image.nix")
    ];

    modules.aws = {
      enable = true;
      enableSSH = true;
      # "auto" sizes the VHD to fit the closure (~few GB); the actual 200 GB
      # disk is specified at EC2 launch via --block-device-mappings and
      # auto-grows at boot via cloud-init growpart.
      rootVolumeSize = "auto";
    };
    modules.locale.enable = true;

    networking.hostName = "aws-nix-builder";

    nix = {
      settings = {
        max-jobs = "auto";
        cores = 0;
        # Download tuning — EC2 instances have high bandwidth, use it
        http-connections = 128;
        max-substitution-jobs = 128;
        download-buffer-size = 134217728; # 128 MiB
        narinfo-cache-negative-ttl = 0;
        extra-substituters = [
          "https://cache.nixcache.org"
          "https://nix-community.cachix.org"
          "https://nix-gaming.cachix.org"
          "https://rust-overlay.cachix.org"
          "https://attic.xuyh0120.win/lantian"
          "https://cache.garnix.io"
        ];
        extra-trusted-public-keys = [
          "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
          "rust-overlay.cachix.org-1:l2scEhXR2wTljEGAr/OGGykVBVbvHI/phxoBUwxaXkk="
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
          "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        ];
      };
      gc.options = lib.mkForce "--delete-older-than 7d";
    };

    environment.systemPackages = with pkgs; [
      cloud-utils.guest  # growpart for expanding partitions at boot
      curl
      e2fsprogs          # resize2fs for expanding ext4 filesystems
      git
      git-lfs
      htop
      inputs.niks3.packages.${stdenv.hostPlatform.system}.default
      jq
      vim
    ];

    security.sudo.wheelNeedsPassword = lib.mkForce false;

    # SSH key is injected at launch time via cloud-init user-data,
    # so it can be rotated without rebuilding the AMI.
    users.users.builder = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    system.stateVersion = "25.11";
  };

  # Central registry of AMI configurations
  amiConfigs = {
    aws-base-server = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        awsBaseServerConfig
      ];
      extraModules = [];
    };

    aws-base-server-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        awsBaseServerConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-base-server-arm";
      }];
    };

    aws-k8s-node = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        self.nixosModules.app-k8s-master
        awsK8sNodeConfig
      ];
      extraModules = [];
    };

    aws-k8s-node-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        self.nixosModules.servers
        self.nixosModules.app-k8s-master
        awsK8sNodeConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-k8s-node-arm";
      }];
    };

    aws-nix-builder = {
      system = "x86_64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsNixBuilderConfig
      ];
      extraModules = [];
    };

    aws-nix-builder-arm = {
      system = "aarch64-linux";
      hostModules = [
        self.nixosModules.aws
        self.nixosModules.locale
        awsNixBuilderConfig
      ];
      extraModules = [{
        networking.hostName = lib.mkForce "aws-nix-builder-arm";
      }];
    };
  };

  mkAmiSystem = _name: cfg:
    lib.nixosSystem {
      system = cfg.system;

      specialArgs = {
        username = "ali";
        inherit inputs outputs;
        system = cfg.system;
      };

      modules = cfg.hostModules ++ [
        commonAmiModule
      ] ++ cfg.extraModules;
    };

  amiSystems = lib.mapAttrs mkAmiSystem amiConfigs;
in
{
  flake.nixosConfigurations = amiSystems;

  perSystem = { system, ... }: {
    packages = lib.mapAttrs'
      (name: _: lib.nameValuePair "${name}-ami" amiSystems.${name}.config.system.build.images.amazon)
      (lib.filterAttrs (_: cfg: cfg.system == system) amiConfigs);
  };
}
