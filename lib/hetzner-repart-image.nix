# VM-free Hetzner Cloud image builder using systemd-repart.
#
# Produces a raw disk image that boots on BOTH:
#   - Hetzner Cloud x86 (SeaBIOS / legacy BIOS) via GRUB i386-pc [V23,B3]
#   - UEFI (Hetzner ARM, or any UEFI host) via systemd-boot UKI
#
# Built entirely without a VM using fakeroot/unshare. GRUB is installed VM-free:
# grub-mkimage builds core.img, grub-bios-setup writes boot.img to the MBR and
# embeds core.img into the bios_grub partition of the produced raw.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  isX86 = pkgs.stdenv.hostPlatform.isx86_64;
  imageName = "nixos-hetzner-${config.system.nixos.version}-${pkgs.stdenv.hostPlatform.system}";

  # With the bios_grub partition (x86), the GPT layout is:
  #   gpt1 = ESP (00-esp), gpt2 = bios_grub (05-bios), gpt3 = root (10-root)
  rootGptIndex = 3;

  kernel = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
  initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
  kernelParams = lib.concatStringsSep " " config.boot.kernelParams;

  # GRUB config lives on the root ext4 at /boot/grub; core.img's prefix points here.
  grubCfg = pkgs.writeText "grub.cfg" ''
    set timeout=1
    serial --unit=0 --speed=115200
    terminal_input serial console
    terminal_output serial console
    menuentry "NixOS (Hetzner)" {
      linux ${kernel} init=${config.system.build.toplevel}/init ${kernelParams}
      initrd ${initrd}
    }
  '';

  # Self-contained BIOS core.img (reads GPT + ext4, loads linux) + the MBR boot.img.
  grubBios = pkgs.runCommand "hetzner-grub-bios" { } ''
    mkdir -p $out
    ${pkgs.grub2}/bin/grub-mkimage \
      -O i386-pc \
      -p "(hd0,gpt${toString rootGptIndex})/boot/grub" \
      -o $out/core.img \
      biosdisk part_gpt ext2 normal linux configfile boot search search_fs_uuid echo
    cp ${pkgs.grub2}/lib/grub/i386-pc/boot.img $out/boot.img
  '';
in
{
  imports = [
    (modulesPath + "/image/repart.nix")
  ];

  # UKI boot for UEFI — EFI binary and UKI placed as static files in the ESP.
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
    }
    # bios_grub partition (x86 only) — holds GRUB core.img for SeaBIOS boot.
    // lib.optionalAttrs isX86 {
      "05-bios" = {
        repartConfig = {
          Type = "21686148-6449-6E6F-744E-656564454649"; # BIOS boot partition
          Label = "bios";
          SizeMinBytes = "1M";
          SizeMaxBytes = "1M";
        };
      };
    }
    // {
      "10-root" = {
        storePaths = [ config.system.build.toplevel ];
        contents = lib.optionalAttrs isX86 {
          "/boot/grub/grub.cfg".source = grubCfg;
        };
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

  # Output the raw image. GRUB BIOS bytes (boot.img/core.img) are emitted alongside
  # but actually written into the raw by an impure finalize step (grub-bios-setup
  # probes host devices and cannot run in the nix sandbox) — see the publish app.
  system.build.hetznerImage = pkgs.runCommand imageName { } ''
    mkdir -p $out/nix-support

    cp ${config.system.build.image}/${config.image.fileName} $out/${imageName}.raw
    chmod +w $out/${imageName}.raw

    ${lib.optionalString isX86 ''
      mkdir -p $out/grub
      cp ${grubBios}/core.img ${grubBios}/boot.img $out/grub/
    ''}

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
