{ pkgs }: ''
  # -----------------------------------------------------
  # Autostart
  # -----------------------------------------------------

  # Setup XDG for screen sharing
  # exec-once = ~/.config/hypr/scripts/xdg.sh

  # Start Polkit
  # exec-once=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

  # Load Sway Notification Centre Notification Manager
  exec-once = ${pkgs.swaynotificationcenter}/bin/swaync

  # Restore wallpaper and launch waybar
  # exec-once = ${pkgs.swww}/bin/swww img ~/git/alijenkins-wallpapers/static/5440x1440/sakura-mountains.png

  # Load GTK settings
  # exec-once = ~/.config/hypr/scripts/gtk.sh

  # Using hypridle to start hyprlock
  exec-once = ${pkgs.hypridle}/bin/hypridle

  # Start eww daemon
  exec-once = ${pkgs.eww}/bin/ags &

  # Start autostart cleanup
  # exec-once = ~/.config/hypr/scripts/cleanup.sh

  # Start main tools
  exec-once = ${pkgs._1password-gui}/bin/1password
  exec-once = ${pkgs.firefox}/bin/firefox
  exec-once = ${pkgs.steam}/bin/steam
  exec-once = ${pkgs.discord-canary}/bin/discordcanary
  exec-once = ${pkgs.waybar}/bin/waybar
  exec-once = ${pkgs.swww}/bin/swww-daemon
''
