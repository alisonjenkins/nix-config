{ config
, pkgs
, ...
}: {
  environment.sessionVariables = {
    NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
  };

  programs.dconf.enable = true;
  programs.kdeconnect.enable = true;
  environment.systemPackages = with pkgs; [
    # libsForQt5.polonium
    kdePackages.qtbase.out
    kdePackages.plasma-browser-integration
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      } # KDE Connect
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      } # KDE Connect
    ];
  };

  services = {
    desktopManager = {
      plasma6 = {
        enable = true;
      };
    };
    displayManager.defaultSession = "plasma";
  };
}
