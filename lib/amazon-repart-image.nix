# VM-free Amazon AMI image builder using systemd-repart.
#
# Replaces make-disk-image.nix (which requires KVM via vmTools.runInLinuxVM)
# with systemd-repart + UKI (Unified Kernel Image). The image is built
# entirely without a VM using fakeroot/unshare, so it works on any host
# including cross-compilation and standard (non-metal) EC2 instances.
#
# Boot chain: UEFI firmware → systemd-boot → UKI (kernel + initrd + cmdline)
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  amiBootMode = if config.ec2.efi then "uefi" else "legacy-bios";
  imageName = "nixos-amazon-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";
in
{
  imports = [
    (modulesPath + "/virtualisation/amazon-image.nix")
    (modulesPath + "/image/repart.nix")
  ];

  # UEFI boot for NitroTPM, Secure Boot, and forward-compatibility
  ec2.efi = true;

  # Use UKI boot instead of GRUB — the EFI binary and UKI can be placed
  # as static files in the ESP without running bootctl/switch-to-configuration.
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.uki.tries = 0;

  # Fix growpart: the NixOS-wrapped growpart creates temp files in /tmp but
  # the service runs early in boot when /tmp may not be properly mounted.
  # Use /run (tmpfs, always available) as TMPDIR instead.
  systemd.services.growpart.environment.TMPDIR = "/run";
  systemd.services.growpart.environment.TEMP = "/run";
  systemd.services.growpart.environment.TMP = "/run";

  image.repart = {
    name = imageName;
    sectorSize = 512;

    partitions = {
      "00-esp" = {
        contents = {
          "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "ESP";
          SizeMinBytes = if pkgs.stdenv.hostPlatform.isx86_64 then "256M" else "384M";
        };
      };

      "10-root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "nixos";
          Minimize = "guess";
        };
      };
    };
  };

  # Root filesystem matches what repart creates
  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Override amazonImage to convert the repart raw image to VHD with metadata
  system.build.amazonImage = lib.mkForce (
    pkgs.runCommand imageName { } ''
      mkdir -p $out/nix-support

      # Convert raw image to VHD (vpc format) for AWS import
      ${pkgs.qemu-utils}/bin/qemu-img convert \
        -f raw -O vpc \
        ${config.system.build.image}/${config.image.fileName} \
        $out/${imageName}.vhd

      echo "file vpc-image $out/${imageName}.vhd" >> $out/nix-support/hydra-build-products

      ${pkgs.jq}/bin/jq -n \
        --arg system_version ${lib.escapeShellArg config.system.nixos.version} \
        --arg system ${lib.escapeShellArg pkgs.stdenv.hostPlatform.system} \
        --arg logical_bytes "$(${pkgs.qemu-utils}/bin/qemu-img info --output json "$out/${imageName}.vhd" | ${pkgs.jq}/bin/jq '."virtual-size"')" \
        --arg boot_mode "${amiBootMode}" \
        --arg file "$out/${imageName}.vhd" \
         '{}
         | .label = $system_version
         | .boot_mode = $boot_mode
         | .system = $system
         | .logical_bytes = $logical_bytes
         | .file = $file
         | .disks.root.logical_bytes = $logical_bytes
         | .disks.root.file = $file
         ' > $out/nix-support/image-info.json
    ''
  );

  image.extension = "raw";
}
