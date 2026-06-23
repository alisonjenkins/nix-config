{ config, lib, pkgs, ... }:
let
  cfg = config.modules.libvirtd;
in
{
  options.modules.libvirtd = {
    enable = lib.mkEnableOption "libvirt virtualization";

    parallelShutdown = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of VMs to shut down in parallel.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      parallelShutdown = cfg.parallelShutdown;
      # Gracefully ACPI-shutdown guests on host shutdown/reboot instead of the
      # default "suspend" (managedsave). VMs with PCI <hostdev> passthrough
      # (home-k8s-master-1 GPU, home-storage-server-1 HBA) cannot be
      # managed-saved — libvirt-guests would fail the save and hard-kill them
      # ungracefully on every host reboot. "shutdown" avoids that.
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm.override { cephSupport = false; };
        runAsRoot = true;
        swtpm.enable = true;
        vhostUserPackages = [ pkgs.virtiofsd ];
      };
    };

    environment = {
      systemPackages = [
        (pkgs.OVMF.override {
          secureBoot = true;
          tpmSupport = true;
        })
      ];
    };
  };
}
