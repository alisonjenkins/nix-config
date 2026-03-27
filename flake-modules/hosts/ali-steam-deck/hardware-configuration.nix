{ ... }: {
  flake.nixosModules.ali-steam-deck-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    boot = {
      kernelModules = [ "kvm-amd" ];
      extraModulePackages = [ ];

      initrd = {
        availableKernelModules = [
          "ahci"
          "cryptd"
          "ehci_pci"
          "nvme"
          "sd_mod"
          "sr_mod"
          "uas"
          "usb_storage"
          "usbhid"
          "virtio_blk"
          "virtio_pci"
          "xhci_pci"
        ];
        kernelModules = [ "dm-snapshot" ];
      };
    };

    fileSystems."/" = {
      device = "/dev/vg/root";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-partlabel/esp";
      fsType = "vfat";
    };

    swapDevices = [
      { device = "/dev/vg/swap"; }
    ];

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
