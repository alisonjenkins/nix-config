{pkgs}: ''
  {
      "label" : "lock",
      "action" : "${pkgs.hyprlock}/bin/hyprlock --config ~/.config/hypr/conf/hyprlock.conf",
      "text" : "Lock",
      "keybind" : "l"
  }
  {
      "label" : "hibernate",
      "action" : "${pkgs.systemd}/bin/systemctl hibernate",
      "text" : "Hibernate",
      "keybind" : "h"
  }
  {
      "label" : "logout",
      "action" : "${pkgs.hyprland}/bin/hyprctl dispatch exit",
      "text" : "Logout",
      "keybind" : "e"
  }
  {
      "label" : "shutdown",
      "action" : "${pkgs.systemd}/bin/systemctl poweroff",
      "text" : "Shutdown",
      "keybind" : "S"
  }
  {
      "label" : "suspend",
      "action" : "${pkgs.systemd}/bin/systemctl suspend",
      "text" : "Suspend",
      "keybind" : "s"
  }
  {
      "label" : "reboot",
      "action" : "${pkgs.systemd}/bin/systemctl reboot",
      "text" : "Reboot",
      "keybind" : "r"
  }
''
