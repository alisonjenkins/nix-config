{ ... }: {
  flake.nixosModules.ali-steam-deck-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    boot = {
      kernelModules = [ "kvm-amd" ];
      extraModulePackages = [ ];

      initrd = {
        availableKernelModules = [
          "nvme"
          "sd_mod"
          "sdhci_pci"
          "usb_storage"
          "xhci_pci"
        ];
        kernelModules = [ ];
      };
    };

    networking.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
