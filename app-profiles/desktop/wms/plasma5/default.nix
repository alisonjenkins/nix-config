{ config, pkgs, user, ... }: {
  environment.systemPackages = with pkgs; [

  ];

  services.xserver.desktopManager.plasma5.enable = true;
}
