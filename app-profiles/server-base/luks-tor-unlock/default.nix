{ config, lib, pkgs, ... }:
{
  # ssh setup
  boot.initrd.network.enable = true;
  boot.initrd.network.ssh = {
    enable = true;
    port = 22;
    shell = "/bin/cryptsetup-askpass";
    authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
    hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
