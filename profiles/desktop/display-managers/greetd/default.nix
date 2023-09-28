{ config, lib, pkgs, ... }:
{
  services = {
    greetd = {
      enable = true;
    };
  };

  programs.regreet = {
    enable = true;
    settings = {
      gtk = {
        application_prefer_dark_theme = true;
        cursor_theme_name = "Adwaita";
        font_name = "Cantarell 16";
        icon_theme_name = "Adwaita";
        theme_name = "Adwaita";
      };

      commands = {
        reboot = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
    };
  };
}
