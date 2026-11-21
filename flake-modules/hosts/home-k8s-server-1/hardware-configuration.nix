{ ... }: {
  # Bare metal: Compulab fitlet2, Intel Celeron J3455 (Apollo Lake), UEFI,
  # one Kingston SATA SSD, three Intel i210/i211 NICs (igb).
  flake.nixosModules.home-k8s-server-1-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # Only used by `just test-build` (nixos-rebuild build-vm); see
    # modules/base/vm-variant.nix.
    vmVariantSettings = {
      memorySize = 4096;
      cores = 4;
      diskSize = 32768; # 32GB
    };

    boot = {
      kernelModules = [ "kvm-intel" ];
      extraModulePackages = [ ];

      initrd = {
        availableKernelModules = [
          "ahci"
          "cryptd"
          "igb"
          "sd_mod"
          "usb_storage"
          "usbhid"
          "xhci_pci"
        ];
        kernelModules = [ "dm-snapshot" ];
      };
    };

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
