{ config, pkgs, user, ... }: {
  environment.sessionVariables = {
    NIX_PROFILES = "${pkgs.lib.concatStringsSep " " (pkgs.lib.reverseList config.environment.profiles)}";
  };

  programs.dconf.enable = true;
  programs.kdeconnect.enable = true;
  environment.systemPackages = with pkgs; [ plasma-browser-integration ];

  networking.firewall = {
    enable = true;
    allowedTCPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
    allowedUDPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
  };

  services = {
    xserver = {
      enable = false;
      desktopManager = {
        plasma6 = {
          enable = true;
        };
      };
    };
  };
}

