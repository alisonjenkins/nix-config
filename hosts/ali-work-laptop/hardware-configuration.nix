{ config
, lib
, modulesPath
, ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot = {
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];

    initrd = {
      availableKernelModules = [ "xhci_pci" "nvme" "ahci" "uas" "usbhid" "usb_storage" "sd_mod" "sr_mod" "virtio_blk" "ehci_pci" "cryptd" "virtio_pci" ];
      kernelModules = [ "dm-snapshot" ];
      luks.devices.luksroot = {
        device = "/dev/disk/by-partlabel/osvg";
        preLVM = true;
        allowDiscards = true;
      };
    };
  };

  fileSystems = {
    "/".neededForBoot = true;
    "/nix".neededForBoot = true;
    "/persistence".neededForBoot = true;
    "/media/storage" = {
      label = "storage";
      fsType = "ext4";
      neededForBoot = false;
    };
  };

  swapDevices = [
    { device = "/dev/osvg/swap"; }
  ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp16s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

