{ pkgs }: ''
  {
      "label" : "lock",
      "action" : "${pkgs.hyprlock}/bin/hyprlock",
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
      "action" : "${pkgs.uwsm}/bin/uwsm stop",
      "text" : "Logout",
      "keybind" : "L"
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
