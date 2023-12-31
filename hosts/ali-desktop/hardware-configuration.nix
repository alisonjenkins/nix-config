# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot = {
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];

    initrd = {
      availableKernelModules = [
        "aesni_intel"
        "ahci"
        "cryptd"
        "dm-raid"
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
      kernelModules = [
        "amdgpu"
        "dm-raid"
        "dm-snapshot"
      ];
      luks.devices.luksroot = {
        device = "/dev/disk/by-uuid/251edf6c-ec46-4734-97ad-1caab10a6246";
        preLVM = true;
        allowDiscards = true;
      };
    };
  };

  virtualisation.vmVariant = {
    diskSize = 65536;
    cores = 8;
    memorySize = 4096;
  };

  fileSystems."/" = {
    device = "/dev/osvg/nixroot";
    fsType = "ext4";
    options = [ "defaults" "noatime" "discard" ];
  };

  fileSystems."/media/archroot" = {
    device = "/dev/osvg/root";
    fsType = "ext4";
    options = [ "defaults" "noatime" "discard" ];
  };

  fileSystems."/media/storage1" = {
    device = "/dev/disk/by-label/storage";
    fsType = "xfs";
    options = [ "defaults" "noatime" "discard" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/12AE-8C8B";
    fsType = "vfat";
  };

  fileSystems."/home" = {
    device = "/dev/home/home";
    fsType = "ext4";
  };

  fileSystems."/media/steam-games-1" = {
    device = "/dev/osvg/steam-games-1";
    fsType = "ext4";
    options = [ "defaults" "noatime" "barrier=0" "data=writeback" "discard" ];
  };

  swapDevices = [{ device = "/dev/osvg/swap"; }];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp16s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
}
