{ config, lib, ... }:
let
  cfg = config.modules.desktop-kde-connect;
in
{
  options.modules.desktop-kde-connect = {
    enable = lib.mkEnableOption "KDE Connect with firewall rules";
  };

  config = lib.mkIf cfg.enable {
    programs.kdeconnect.enable = true;

    networking.firewall = {
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
  };
}
