{ pkgs, inputs, system}: ''
  # -----------------------------------------------------
  # Autostart
  # -----------------------------------------------------

  # Allow hyprshade to adjust filters
  exec-once = dbus-update-activation-environment --systemd HYPRLAND_INSTANCE_SIGNATURE

  # Setup XDG for screen sharing
  # exec-once = ~/.config/hypr/scripts/xdg.sh

  # Start Polkit
  # exec-once=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

  # Load Sway Notification Centre Notification Manager
  # exec-once = ${pkgs.swaynotificationcenter}/bin/swaync

  # Load shell
  exec-once = ${inputs.quickshell.packages.${system}.default}/bin/quickshell -c caelestia

  # Load GTK settings
  # exec-once = ~/.config/hypr/scripts/gtk.sh

  # Start autostart cleanup
  # exec-once = ~/.config/hypr/scripts/cleanup.sh

  # Start main tools
  exec-once = ${pkgs._1password-gui}/bin/1password
  exec-once = ${pkgs.discord-canary}/bin/discordcanary
  exec-once = ${pkgs.swww}/bin/swww-daemon
  exec-once = ${pkgs.blueman}/bin/blueman-applet
  # exec-once = ${pkgs.eww}/bin/eww daemon
  exec-once = ${pkgs.swww}/bin/swww-daemon

  # Restore wallpaper
  exec-once = ${pkgs.swww}/bin/swww img ~/git/alijenkins-wallpapers/static/5440x1440/sakura-mountains.png
  # exec-once = ${pkgs.eww}/bin/eww open bar

  # Blue light filter
  exec = ${pkgs.hyprshade}/bin/hyprshade auto
''
