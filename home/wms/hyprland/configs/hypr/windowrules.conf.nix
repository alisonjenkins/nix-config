''
  # -----------------------------------------------------
  # Window rules
  # -----------------------------------------------------

  windowrule = float,^(pavucontrol)$
  windowrule = float,^(blueman-manager)$
  windowrule = float,^(nm-connection-editor)$
  windowrule = float,^(nm-connection-editor)$

  # windowrulev2 = workspace 4, class:steam
  windowrulev2 = fullscreenstate:* 2, class:Alacritty
  windowrulev2 = workspace 10, class:(1Password)
  windowrulev2 = workspace 1, class:discord
  windowrulev2 = workspace 1, class:vesktop
  windowrulev2 = workspace 2, class:Alacritty
  windowrulev2 = workspace 3, class:firefox

  # Browser Picture in Picture
  windowrulev2 = float, title:^(Picture-in-Picture)$
  windowrulev2 = pin, title:^(Picture-in-Picture)$
  windowrulev2 = move 69.5% 4%, title:^(Picture-in-Picture)$
''
