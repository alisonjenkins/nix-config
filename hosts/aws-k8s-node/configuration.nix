{ modulesPath, lib, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/amazon-image.nix")
    ../../modules/aws
    ../../modules/locale
    ../../modules/servers
    ../../app-profiles/k8s-master
  ];

  modules.aws = {
    enable = true;
    rootVolumeSize = 20;
  };

  modules.locale.enable = true;

  modules.servers = {
    enable = true;
    openPrometheusFirewallPort = false;
  };

  networking.hostName = "aws-k8s-node";

  security.sudo.wheelNeedsPassword = lib.mkForce false;

  system.stateVersion = "25.11";

  users.users.ali = {
    isNormalUser = true;
    description = "Alison Jenkins";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
    ];
  };
}
