{ ... }: {
  flake.nixosModules.dev-vm-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    # Note: dev-vm doesn't use the base module, so VM variant is configured manually
    virtualisation.vmVariant = {
      virtualisation = {
        memorySize = 2048;
        cores = 4;
        diskSize = 20480; # 20GB
      };
    };

    boot = {
      kernelModules = [ "virtio_gpu" ];
      extraModulePackages = [ ];

      initrd = {
        availableKernelModules = [ "xhci_pci" "nvme" "ahci" "uas" "usbhid" "usb_storage" "sd_mod" "sr_mod" "virtio_blk" "ehci_pci" "cryptd" "virtio_pci" "virtio_gpu" ];
        kernelModules = [ "dm-snapshot" "virtio_gpu" ];
      };
    };

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  };
}
