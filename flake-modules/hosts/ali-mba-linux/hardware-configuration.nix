{ ... }: {
  flake.nixosModules.ali-mba-linux-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot = {
      kernelModules = [ ];
      extraModulePackages = [ ];

      initrd = {
        # USB + NVMe enough to boot the asahi installer's ext4 root.
        # Asahi kernel + m1n1 handle the GPU/audio side; nothing
        # needs to come in via initrd kernelModules.
        availableKernelModules = [
          "usb_storage"
          "sd_mod"
          "uas"
          "nvme"
          "usbhid"
          "xhci_pci"
        ];
        kernelModules = [ ];
        # Required when impermanence is later enabled (pass 2).
        systemd.enable = true;
      };
    };

    # Initial install layout — plain ext4 root. asahi-installer creates
    # the EFI partition (FAT32, labeled "EFI - NIXOS") and a stub apfs
    # for m1n1; the Linux root is hand-created with `sgdisk -n 0:0 -s`
    # in the free space between them and formatted `mkfs.ext4 -L nixos`.
    #
    # The EFI partition is referenced via the asahi-marked kernel node
    # rather than its label — there can be other FAT32 partitions on
    # disk (RecoveryOSContainer is apfs but the layout is fragile), and
    # /proc/device-tree/chosen/asahi,efi-system-partition is guaranteed
    # to point at the NixOS one created by the asahi installer.
    #
    # Capture the partuuid post-install:
    #   lsblk -o NAME,PARTUUID /dev/nvme0n1p4
    # and paste it into the device line below. Until then this file is
    # a template — `nixos-rebuild` will refuse to evaluate with the
    # placeholder string.
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        options = [ "noatime" "discard" ];
      };
      "/boot" = {
        device = "/dev/disk/by-partuuid/REPLACE-WITH-EFI-PARTUUID-AT-INSTALL-TIME";
        fsType = "vfat";
        options = [ "fmask=0077" "dmask=0077" ];
      };
    };

    # Impermanence variant — apply after the plain layout boots
    # successfully and you've verified m1n1 -> u-boot -> systemd-boot
    # -> asahi kernel works end-to-end. Replace the fileSystems block
    # above with:
    #
    #   "/" = { fsType = "tmpfs"; options = [ "defaults" "size=8G" "mode=755" ]; };
    #   "/nix" = {
    #     device = "/dev/disk/by-label/nixos";
    #     fsType = "ext4";
    #     options = [ "noatime" "discard" ];
    #     neededForBoot = true;
    #   };
    #   "/persistence" = {
    #     device = "/nix/persistence";
    #     options = [ "bind" ];
    #     depends = [ "/nix" ];
    #     neededForBoot = true;
    #   };
    #   "/boot" = { device = "/dev/disk/by-partuuid/<PARTUUID>"; fsType = "vfat"; };
    #
    # And flip `modules.base.enableImpermanence = true` in default.nix.

    swapDevices = [ ];

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  };
}
