{ ... }: {
  flake.nixosModules.home-k8s-master-1-hardware = { lib, pkgs, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

    # VM variant configuration is now handled by the base module
    # See modules/base/vm-variant.nix
    vmVariantSettings = {
      memorySize = 4096;
      cores = 4;
      diskSize = 32768; # 32GB
    };

    boot.extraModulePackages = [ ];
    # virtio-only guest: the physical-host module list (ahci/sdhci/usb) came
    # from the original bare-metal install. includeDefaultModules already
    # covers the virtio set; dm-snapshot stays for LVM.
    boot.initrd.availableKernelModules = [ "xhci_pci" "sd_mod" ];
    boot.initrd.kernelModules = [ "dm-snapshot" ];
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.kernelPatches = [
      {
        name = "enable-netkit";
        patch = null;
        extraConfig = ''
          NETKIT y
        '';
      }
    ];

    # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
    # (the default) this is the recommended approach. When using systemd-networkd it's
    # still possible to use this option, but it's recommended to use it in conjunction
    # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
    networking.useDHCP = lib.mkDefault true;
    # networking.interfaces.eno1.useDHCP = lib.mkDefault true;
    # networking.interfaces.enp1s0.useDHCP = lib.mkDefault true;
    # networking.interfaces.enp3s0.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  };
}
