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
    curl
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
