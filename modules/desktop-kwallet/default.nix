{ config, lib, ... }:
let
  cfg = config.modules.desktop-kwallet;
in
{
  options.modules.desktop-kwallet = {
    enable = lib.mkEnableOption "KDE Wallet PAM integration";
  };

  config = lib.mkIf cfg.enable {
    security.pam.services = {
      greetd = {
        kwallet = {
          enable = true;
        };
      };

      kde = {
        kwallet = {
          enable = true;
        };
      };

      login = {
        kwallet = {
          enable = true;
        };
      };
    };
  };
}
