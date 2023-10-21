{ config, pkgs, user, ... }: {
  environment.sessionVariables = {
    NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
  };

  programs.dconf.enable = true;
  security.pam.services.greetd.enableKwallet = true;

  services = {
    xserver = {
      enable = true;
      desktopManager = {
        plasma5 = {
          enable = true;
        };
      };
    };
  };
}
