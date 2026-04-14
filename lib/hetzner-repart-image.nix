# VM-free Hetzner Cloud image builder using systemd-repart.
#
# Produces a raw disk image with UEFI boot via UKI (Unified Kernel Image).
# Built entirely without a VM using fakeroot/unshare, so it works on any host
# including cross-compilation.
#
# Boot chain: UEFI firmware → systemd-boot → UKI (kernel + initrd + cmdline)
#
# The raw image can be uploaded to Hetzner Cloud as a snapshot using
# hcloud-upload-image or the rescue mode approach.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  imageName = "nixos-hetzner-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";
in
{
  imports = [
    (modulesPath + "/image/repart.nix")
  ];

  # Use UKI boot — EFI binary and UKI placed as static files in the ESP.
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.uki.tries = 0;

  # Fix growpart: use /run as TMPDIR since /tmp may not be mounted early in boot.
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

  # Output the raw image with metadata
  system.build.hetznerImage = pkgs.runCommand imageName { } ''
    mkdir -p $out/nix-support

    cp ${config.system.build.image}/${config.image.fileName} $out/${imageName}.raw

    echo "file raw-image $out/${imageName}.raw" >> $out/nix-support/hydra-build-products

    ${pkgs.jq}/bin/jq -n \
      --arg system_version ${lib.escapeShellArg config.system.nixos.version} \
      --arg system ${lib.escapeShellArg pkgs.stdenv.hostPlatform.system} \
      --arg logical_bytes "$(stat -c %s "$out/${imageName}.raw")" \
      --arg file "$out/${imageName}.raw" \
       '{}
       | .label = $system_version
       | .system = $system
       | .logical_bytes = $logical_bytes
       | .file = $file
       ' > $out/nix-support/image-info.json
  '';

  image.extension = "raw";
}
