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
    # Pinned off linuxPackages_latest (was 7.1.7, floated to 7.2): Linux 7.2
    # removed strncpy() entirely, and the legacy proprietary nvidia driver
    # (nvidiaPackages.legacy_580 -- the only track that supports the
    # passed-through GTX 1070/Pascal for NVENC transcode; open-gpu-kernel-modules
    # only supports Turing+) still calls it directly in os-interface.c, so it
    # fails to build against 7.2+. 7.1.10 is a small patch bump from the
    # previously-running 7.1.7, still pre-strncpy-removal, same nixpkgs
    # channel as everything else (not the nixpkgs_old/24.11 branch).
    #
    # TEMPORARY. Tracked in alisonjenkins/nix-config#226. The scheduled
    # canary in .github/workflows/nvidia-kernel-canary.yml builds
    # nvidiaPackages.legacy_580 against linuxPackages_latest weekly and
    # fails the moment that combination works again -- that's the signal to
    # revert this back to pkgs.linuxPackages_latest and close the issue.
    boot.kernelPackages = pkgs.linuxKernel.packages.linux_7_1;
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
