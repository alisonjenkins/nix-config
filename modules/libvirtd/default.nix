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
