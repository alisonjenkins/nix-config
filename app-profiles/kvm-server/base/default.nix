{ config, pkgs, lib, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    parallelShutdown = 4;
    qemu = {
      swtpm.enable = true;
    };
  };
  networking.interfaces.br0.useDHCP = true;
  networking.bridges = {
    "br0" = {
      interfaces = [ "enp12s0" ];
    };
  };
}
