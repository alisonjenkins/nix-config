# Btrfs overrides for the Amazon AMI image builder.
#
# This module is used as `image.modules.amazon` to replace the default
# amazon-image.nix. It includes the upstream module via disabledModules +
# re-import to avoid path deduplication issues, then overrides the builder.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.amazonImage;
  amiBootMode = if config.ec2.efi then "uefi" else "legacy-bios";
  makeBtrfsAmiImage = ./make-btrfs-ami-image.nix;

  # Canonical path to amazon-image.nix — must match what images.nix uses
  # so NixOS deduplicates correctly
  upstreamAmazonImage = modulesPath + "/../maintainers/scripts/ec2/amazon-image.nix";
in
{
  imports = [
    upstreamAmazonImage
  ];

  # Override the root filesystem to btrfs with compression
  fileSystems."/" = {
    device = lib.mkForce "/dev/disk/by-label/nixos";
    fsType = lib.mkForce "btrfs";
    autoResize = lib.mkForce true;
    options = lib.mkForce [ "compress=zstd:3" "noatime" "ssd" "discard=async" ];
  };

  # Ensure btrfs is available in initrd for root mount
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  # Override the image builder to use our btrfs builder
  system.build.amazonImage = lib.mkForce (
    let
      configFile = pkgs.writeText "configuration.nix" ''
        { modulesPath, ... }: {
          imports = [ "''${modulesPath}/virtualisation/amazon-image.nix" ];
          ${lib.optionalString config.ec2.efi ''
            ec2.efi = true;
          ''}
        }
      '';
    in
    import makeBtrfsAmiImage {
      inherit lib config configFile pkgs;
      inherit (cfg) contents format;
      inherit (config.image) baseName;
      inherit (config.virtualisation) diskSize;

      postVM = ''
        mkdir -p $out/nix-support
        echo "file ${cfg.format} $diskImage" >> $out/nix-support/hydra-build-products

        ${pkgs.jq}/bin/jq -n \
          --arg system_version ${lib.escapeShellArg config.system.nixos.version} \
          --arg system ${lib.escapeShellArg pkgs.stdenv.hostPlatform.system} \
          --arg logical_bytes "$(${pkgs.qemu-utils}/bin/qemu-img info --output json "$diskImage" | ${pkgs.jq}/bin/jq '."virtual-size"')" \
          --arg boot_mode "${amiBootMode}" \
          --arg file "$diskImage" \
           '{}
           | .label = $system_version
           | .boot_mode = $boot_mode
           | .system = $system
           | .logical_bytes = $logical_bytes
           | .file = $file
           | .disks.root.logical_bytes = $logical_bytes
           | .disks.root.file = $file
           ' > $out/nix-support/image-info.json
      '';
    }
  );
}
