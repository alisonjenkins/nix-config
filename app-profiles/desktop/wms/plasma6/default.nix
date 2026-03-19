{ config
, pkgs
, ...
}: {
  environment.sessionVariables = {
    NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
  };

  programs.dconf.enable = true;
  environment.systemPackages = with pkgs; [
    # libsForQt5.polonium
    kdePackages.qtbase.out
    kdePackages.plasma-browser-integration
  ];

  services = {
    desktopManager = {
      plasma6 = {
        enable = true;
      };
    };
    displayManager.defaultSession = "plasma";
  };
}
