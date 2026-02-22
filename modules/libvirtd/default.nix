{ config, lib, pkgs, ... }:
let
  cfg = config.modules.libvirtd;
in
{
  options.modules.libvirtd = {
    enable = lib.mkEnableOption "libvirt virtualization";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
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
