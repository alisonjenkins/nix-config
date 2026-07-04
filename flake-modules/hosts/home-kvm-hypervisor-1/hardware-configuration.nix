{ ... }: {
  flake.nixosModules.home-kvm-hypervisor-1-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # VM variant configuration is now handled by the base module
    # See modules/base/vm-variant.nix
    vmVariantSettings = {
      memorySize = 4096;
      cores = 8;
      diskSize = 65536; # 64GB
      # This host uses GRUB, so don't auto-configure systemd-boot
      configureBootLoader = false;
    };

    boot = {
      kernelModules = [ "kvm-amd" ];
      extraModulePackages = [ ];
      extraModprobeConfig = ''
        softdep drm pre: vfio-pci
        softdep mpt3sas pre: vfio-pci
      '';

      initrd = {
        availableKernelModules = [ "xhci_pci" "nvme" "ahci" "uas" "usbhid" "usb_storage" "sd_mod" "sr_mod" "virtio_blk" "ehci_pci" "cryptd" "virtio_pci" ];
        kernelModules = [ "dm-snapshot" "vfio-pci" "vfio" "vfio_iommu_type1" ];
      };
    };

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    # Pull in redistributable CPU microcode. updateMicrocode below follows this
    # flag, which was previously unset (=false), so no AMD microcode was applied.
    # Required ahead of the EPYC 7543P / ROMED8-2T swap: server silicon wants the
    # early-boot microcode update present in initrd.
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
