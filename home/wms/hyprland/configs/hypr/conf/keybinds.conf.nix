{ pkgs, ... }: ''
  # SUPER KEY
  $mainMod = SUPER
  # $HYPRSCRIPTS = ~/.config/hypr/scripts
  # $SCRIPTS = ~/.config/ml4w/scripts

  # Applications
  bind = $mainMod, RETURN, exec, ${pkgs.alacritty}/bin/alacritty # Open terminal
  bind = $mainMod, B, exec, ${pkgs.firefox}/bin/firefox # Open the browser
  bind = $mainMod, E, exec, ${pkgs.pcmanfm}/bin/pcmanfm # Open the filemanager

  # Push to talk passthrough
  bind = CTRL, , pass, ^discord$

  # Windows
  # bind = $mainMod SHIFT, T, exec, $HYPRSCRIPTS/toggleallfloat.sh # Toggle all windows into floating mode
  bind = $mainMod SHIFT, h, resizeactive, -100 0 # Reduce window width with keyboard
  bind = $mainMod SHIFT, j, resizeactive, 0 100 # Increase window height with keyboard
  bind = $mainMod SHIFT, k, resizeactive, 0 -100 # Reduce window height with keyboard
  bind = $mainMod SHIFT, l, resizeactive, 100 0 # Increase window width with keyboard
  bind = $mainMod, f, fullscreen # Set active window to fullscreen
  bind = $mainMod, h, movefocus, l # Move focus left
  bind = $mainMod, j, movefocus, d # Move focus down
  bind = $mainMod, k, movefocus, u # Move focus up
  bind = $mainMod, l, movefocus, r # Move focus right
  bind = $mainMod, q, killactive # Kill active window
  bind = $mainMod, t, togglefloating # Toggle active windows into floating mode
  bindm = $mainMod, mouse:272, movewindow # Move window with the mouse
  bindm = $mainMod, mouse:273, resizewindow # Resize window with the mouse

  # Actions
  # bind = $mainMod CTRL, K, exec, $HYPRSCRIPTS/keybindings.sh # Show keybindings
  # bind = $mainMod CTRL, T, exec, ~/.config/waybar/themeswitcher.sh # Open waybar theme switcher
  # bind = $mainMod SHIFT, A, exec, $HYPRSCRIPTS/toggle-animations.sh # Toggle animations
  # bind = $mainMod SHIFT, B, exec, ~/.config/waybar/launch.sh # Reload waybar
  # bind = $mainMod SHIFT, H, exec, $HYPRSCRIPTS/hyprshade.sh # Toggle screenshader
  # bind = $mainMod SHIFT, S, exec, $HYPRSCRIPTS/screenshot.sh # Take a screenshot
  # bind = $mainMod, PRINT, exec, $HYPRSCRIPTS/screenshot.sh # Take a screenshot

  # Reload hyprland config
  bind = $mainMod SHIFT, R, exec, ${pkgs.hyprland}/bin/hyprctl reload

  # Toggle waybar
  bind = $mainMod CTRL, B, exec, ${pkgs.psmisc}/bin/killall -SIGUSR1 .waybar-wrapped

  # Open wallpaper selector bind = $mainMod ALT, W, exec, $HYPRSCRIPTS/wallpaper-automation.sh # Start random wallpaper script
  bind = $mainMod CTRL, W, exec, ${pkgs.waypaper}/bin/waypaper                                                             

  # Start wleave
  bind = $mainMod, DELETE, exec, ${pkgs.wleave}/bin/wleave --show-keybinds --layout ~/.config/hypr/conf/wleave-layout.conf

  # Change the wallpaper
  bind = $mainMod SHIFT, W, exec, ${pkgs.waypaper}/bin/waypaper --random

  # Open application launcher-
  bind = $mainMod, D, exec, ${pkgs.wofi}/bin/wofi --show drun 

  # Workspaces
  bind = $mainMod, 1, workspace, 1 # Open workspace 1
  bind = $mainMod, 2, workspace, 2 # Open workspace 2
  bind = $mainMod, 3, workspace, 3 # Open workspace 3
  bind = $mainMod, 4, workspace, 4 # Open workspace 4
  bind = $mainMod, 5, workspace, 5 # Open workspace 5
  bind = $mainMod, 6, workspace, 6 # Open workspace 6
  bind = $mainMod, 7, workspace, 7 # Open workspace 7
  bind = $mainMod, 8, workspace, 8 # Open workspace 8
  bind = $mainMod, 9, workspace, 9 # Open workspace 9
  bind = $mainMod, 0, workspace, 10 # Open workspace 10

  bind = $mainMod SHIFT, 1, movetoworkspace, 1 # Move active window to workspace 1
  bind = $mainMod SHIFT, 2, movetoworkspace, 2 # Move active window to workspace 2
  bind = $mainMod SHIFT, 3, movetoworkspace, 3 # Move active window to workspace 3
  bind = $mainMod SHIFT, 4, movetoworkspace, 4 # Move active window to workspace 4
  bind = $mainMod SHIFT, 5, movetoworkspace, 5 # Move active window to workspace 5
  bind = $mainMod SHIFT, 6, movetoworkspace, 6 # Move active window to workspace 6
  bind = $mainMod SHIFT, 7, movetoworkspace, 7 # Move active window to workspace 7
  bind = $mainMod SHIFT, 8, movetoworkspace, 8 # Move active window to workspace 8
  bind = $mainMod SHIFT, 9, movetoworkspace, 9 # Move active window to workspace 9
  bind = $mainMod SHIFT, 0, movetoworkspace, 10 # Move active window to workspace 10

  bind = $mainMod, Tab, workspace, m+1 # Open next workspace
  bind = $mainMod SHIFT, Tab, workspace, m-1 # Open previous workspace

  bind = $mainMod CTRL, 1, exec, $HYPRSCRIPTS/moveTo.sh 1 # Move all windows to workspace 1
  bind = $mainMod CTRL, 2, exec, $HYPRSCRIPTS/moveTo.sh 2 # Move all windows to workspace 2
  bind = $mainMod CTRL, 3, exec, $HYPRSCRIPTS/moveTo.sh 3 # Move all windows to workspace 3
  bind = $mainMod CTRL, 4, exec, $HYPRSCRIPTS/moveTo.sh 4 # Move all windows to workspace 4
  bind = $mainMod CTRL, 5, exec, $HYPRSCRIPTS/moveTo.sh 5 # Move all windows to workspace 5
  bind = $mainMod CTRL, 6, exec, $HYPRSCRIPTS/moveTo.sh 6 # Move all windows to workspace 6
  bind = $mainMod CTRL, 7, exec, $HYPRSCRIPTS/moveTo.sh 7 # Move all windows to workspace 7
  bind = $mainMod CTRL, 8, exec, $HYPRSCRIPTS/moveTo.sh 8 # Move all windows to workspace 8
  bind = $mainMod CTRL, 9, exec, $HYPRSCRIPTS/moveTo.sh 9 # Move all windows to workspace 9
  bind = $mainMod CTRL, 0, exec, $HYPRSCRIPTS/moveTo.sh 10 # Move all windows to workspace 10

  bind = $mainMod, mouse_down, workspace, e+1 # Open next workspace
  bind = $mainMod, mouse_up, workspace, e-1 # Open previous workspace
  bind = $mainMod CTRL, down, workspace, empty # Open the next empty workspace

  # Passthrough SUPER KEY to Virtual Machine
  bind = $mainMod, P, submap, passthru # Passthrough SUPER key to virtual machine
  submap = passthru
  bind = SUPER, Escape, submap, reset # Get SUPER key back from virtual machine
  submap = reset

  # Fn keys
  bind = , XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl -q s +10% # Increase brightness by 10%
  bind = , XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl -q s 10%- # Reduce brightness by 10%
  bind = , XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 5%+ # Increase volume by 5%
  bind = , XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 5%- # Reduce volume by 5%
  bind = , XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle # Toggle mute
  bind = , XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause # Audio play pause
  bind = , XF86AudioPause, exec, ${pkgs.playerctl}/bin/playerctl pause # Audio pause
  bind = , XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next # Audio next
  bind = , XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous # Audio previous
  bind = , XF86AudioMicMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_SOURCE@ toggle # Toggle microphone
  bind = , XF86Lock, exec, ${pkgs.hyprlock}/bin/hyprlock --config ~/.config/hypr/conf/hyprlock.conf # Open screenlock
  bind = , code:238, exec, ${pkgs.brightnessctl}/bin/brightnessctl -d smc::kbd_backlight s +10
  bind = , code:237, exec, ${pkgs.brightnessctl}/bin/brightnessctl -d smc::kbd_backlight s 10-

  # Remap caps to ctrl
  input {
    kb_options = ctrl:nocaps
  }
''
