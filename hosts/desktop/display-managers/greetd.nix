{ config, lib, pkgs, ... }: {
  services = {
    greetd = {
      enable = true;
    };
  };

  programs.regreet = {
    enable = true;
    settings = ''
      [GTK]
      # Whether to use the dark theme
      application_prefer_dark_theme = true

      # Cursor theme name
      cursor_theme_name = "Adwaita"

      # Font name and size
      font_name = "Cantarell 16"

      # Icon theme name
      icon_theme_name = "Adwaita"

      # GTK theme name
      theme_name = "Adwaita"

      [commands]
      # The command used to reboot the system
      reboot = [ "systemctl", "reboot" ]

      # The command used to shut down the system
      poweroff = [ "systemctl", "poweroff" ]
    '';
  };
}
