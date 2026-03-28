{ modulesPath, lib, pkgs, inputs, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/amazon-image.nix")
    ../../modules/aws
    ../../modules/locale
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
      # Cache "not found" responses for 1h to avoid re-querying caches
      narinfo-cache-negative-ttl = 3600;
      connect-timeout = 5;
      stalled-download-timeout = 10;
      fallback = true;
      extra-substituters = [
        "https://cache.nixcache.org"
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"
      ];
      extra-trusted-public-keys = [
        "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
    gc.options = lib.mkForce "--delete-older-than 7d";
  };

  environment.systemPackages = with pkgs; [
    cloud-utils    # growpart for expanding partitions at boot
    curl
    e2fsprogs      # resize2fs
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
}
