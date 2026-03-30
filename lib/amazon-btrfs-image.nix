# Amazon AMI image module with btrfs root filesystem.
#
# Drop-in replacement for nixpkgs' amazon-image.nix that uses a btrfs builder
# instead of ext4. Imports the upstream amazon-image.nix for EC2 config
# (boot params, cloud-init, etc.) but overrides the image builder.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.amazonImage;
  amiBootMode = if config.ec2.efi then "uefi" else "legacy-bios";
in
{
  imports = [
    # Upstream amazon-image.nix for EC2 config, options, and boot params.
    # We override system.build.amazonImage below to use btrfs.
    (pkgs.path + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
  ];

  # Override the root filesystem to btrfs with compression
  fileSystems."/" = {
    fsType = lib.mkForce "btrfs";
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
    import ./make-btrfs-ami-image.nix {
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
