{ hyprland, config, lib, pkgs, ... }:
{
  home.file.".config/hypr/hyprland.conf".text = ''
  $mainMod = SUPER

  # Monitor
  monitor=,preferred,auto,1,bitdepth,10


  # Fix slow startup
  exec systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
  exec dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

  # Autostart

  exec-once = hyprctl setcursor Bibata-Modern-Classic 24
  exec-once = swaynotificationcenter
  exec-once = kwalletd

  source = /home/ali/.config/hypr/colors
  exec = pkill waybar & sleep 0.5 && waybar
  exec-once = swww init
  # exec = swww img /home/ali/Pictures/wallpapers/wallpaper.jpg

  # Input config
  input {
      kb_layout = us
      kb_variant =
      kb_model =
      kb_options =
      kb_rules =

      follow_mouse = 1

      touchpad {
          natural_scroll = false
      }

      sensitivity = 0
  }

  general {
      gaps_in = 5
      gaps_out = 10
      border_size = 2
      col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
      col.inactive_border = rgba(595959aa)

      layout = dwindle
  }

  decoration {
      rounding = 5

      blur {
          enabled = true
          size = 7
          passes = 4
          new_optimizations = true
      }

      blurls = lockscreen

      drop_shadow = yes
      shadow_range = 4
      shadow_render_power = 3
      col.shadow = rgba(1a1a1aee)
  }

  animations {
      enabled = yes

      bezier = myBezier, 0.10, 0.9, 0.1, 1.05

      animation = windows, 1, 7, myBezier, slide
      animation = windowsOut, 1, 7, myBezier, slide
      animation = border, 1, 10, default
      animation = fade, 1, 7, default
      animation = workspaces, 1, 6, default
  }

  dwindle {
      pseudotile = yes
      preserve_split = yes
  }

  master {
      new_is_master = yes
  }

  gestures {
      workspace_swipe = false
  }

  windowrulev2 = opacity 1 0.8,title:^(.*)$

  windowrule = float, title:^(btop)$
  windowrule = float, title:^(update-sys)$
  windowrule = float,^(blueman-manager)$
  windowrule = float,^(chromium)$
  windowrule = float,^(nm-connection-editor)$
  windowrule = float,^(pavucontrol)$
  windowrule = float,^(thunar)$

  bind = $mainMod, G, fullscreen,

  windowrule = float,^(zoom)$

  windowrulev2 = animation popin,class:^(chromium)$
  windowrulev2 = animation popin,class:^(kitty)$,title:^(update-sys)$
  windowrulev2 = animation popin,class:^(thunar)$
  windowrulev2 = move cursor -3% -105%,class:^(wofi)$
  windowrulev2 = noanim,class:^(wofi)$
  # windowrulev2 = nofocus,class:^(steam)$
  windowrulev2 = opacity 0.8 0.6,class:^(wofi)$
  windowrulev2 = opacity 0.8 0.8,class:^(VSCodium)$
  windowrulev2 = opacity 0.8 0.8,class:^(kitty)$
  windowrulev2 = opacity 0.8 0.8,class:^(thunar)$
  windowrulev2 = workspace 1,class:^(discord)$
  windowrulev2 = workspace 1,class:^(zoom)$
  windowrulev2 = workspace 2,class:^(Alacritty)$
  windowrulev2 = workspace 3,class:^(firefox)$
  # windowrulev2 = workspace 4,class:^(steam)$

  # See https://wiki.hyprland.org/Configuring/Keywords/ for more

  # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
  # bind = ,mouse:275,pass,^(Discord)$

  bind = $mainMod, A, exec, audacity
  bind = $mainMod, C, killactive,
  bind = $mainMod, E, exec, thunar # Show the graphical file browser
  bind = $mainMod, J, togglesplit, # dwindle
  bind = $mainMod, M, exec, wlogout --protocol layer-shell # show the logout window
  bind = $mainMod, P, pseudo, # dwindle
  bind = $mainMod, Q, exec, alacritty
  bind = $mainMod, R, exec, wofi --show drun
  bind = $mainMod, S, exec, grim -g "$(slurp)" - | wl-copy # take a screenshot
  bind = $mainMod, V, togglefloating,
  bind = $mainMod, f, fullscreen,

  # Move focus with mainMod + arrow keys
  bind = $mainMod, h, movefocus, l
  bind = $mainMod, l, movefocus, r
  bind = $mainMod, j, movefocus, u
  bind = $mainMod, k, movefocus, d

  # Switch workspaces with mainMod + [0-9]
  bind = $mainMod, 1, workspace, 1
  bind = $mainMod, 2, workspace, 2
  bind = $mainMod, 3, workspace, 3
  bind = $mainMod, 4, workspace, 4
  bind = $mainMod, 5, workspace, 5
  bind = $mainMod, 6, workspace, 6
  bind = $mainMod, 7, workspace, 7
  bind = $mainMod, 8, workspace, 8
  bind = $mainMod, 9, workspace, 9
  bind = $mainMod, 0, workspace, 10

  # Move active window to a workspace with mainMod + SHIFT + [0-9]
  bind = $mainMod SHIFT, 1, movetoworkspace, 1
  bind = $mainMod SHIFT, 2, movetoworkspace, 2
  bind = $mainMod SHIFT, 3, movetoworkspace, 3
  bind = $mainMod SHIFT, 4, movetoworkspace, 4
  bind = $mainMod SHIFT, 5, movetoworkspace, 5
  bind = $mainMod SHIFT, 6, movetoworkspace, 6
  bind = $mainMod SHIFT, 7, movetoworkspace, 7
  bind = $mainMod SHIFT, 8, movetoworkspace, 8
  bind = $mainMod SHIFT, 9, movetoworkspace, 9
  bind = $mainMod SHIFT, 0, movetoworkspace, 10

  # Scroll through existing workspaces with mainMod + scroll
  bind = $mainMod, mouse_down, workspace, e+1
  bind = $mainMod, mouse_up, workspace, e-1

  # Move/resize windows with mainMod + LMB/RMB and dragging
  bindm = $mainMod, mouse:272, movewindow
  bindm = $mainMod, mouse:273, resizewindow

  source = ~/.config/hypr/media-binds.conf
  source = ~/.config/hypr/env_var.conf
  source = ~/.config/hypr/submaps/submaps.conf

  bind = $mainMod, g, submap, games
  '';

  home.file.".config/hypr/colors".text = ''
    $background = rgba(1d192bee)
    $foreground = rgba(c3dde7ee)

    $color0 = rgba(1d192bee)
    $color1 = rgba(465EA7ee)
    $color2 = rgba(5A89B6ee)
    $color3 = rgba(6296CAee)
    $color4 = rgba(73B3D4ee)
    $color5 = rgba(7BC7DDee)
    $color6 = rgba(9CB4E3ee)
    $color7 = rgba(c3dde7ee)
    $color8 = rgba(889aa1ee)
    $color9 = rgba(465EA7ee)
    $color10 = rgba(5A89B6ee)
    $color11 = rgba(6296CAee)
    $color12 = rgba(73B3D4ee)
    $color13 = rgba(7BC7DDee)
    $color14 = rgba(9CB4E3ee)
    $color15 = rgba(c3dde7ee)
  '';

  home.file.".config/hypr/submaps/submaps.conf".text = ''
    source=~/.config/hypr/submaps/games.conf
    submap=reset
  '';

  home.file.".config/hypr/submaps/games.conf".text = ''
    submap = games
    bind = , a , exec, gtk-launch 'ARMORED CORE VI FIRES OF RUBICON'
    bind = , a, submap, reset
    bind = , b , exec, gtk-launch "Baldur's Gate 3"
    bind = , b, submap, reset
    bind = , j , exec, gtk-launch "Jumplight Odyssey"
    bind = , j, submap, reset
    bind = , d , exec, gtk-launch "DOOM Eternal"
    bind = , d, submap, reset
    bind = , D , exec, gtk-launch "DOOM"
    bind = , D, submap, reset
    bind = , r , exec, gtk-launch "The Riftbreaker"
    bind = , r, submap, reset

    bind = , escape, submap, reset
  '';

  home.file.".config/hypr/media-binds.conf".text = ''
    $SCRIPT = ~/.config/waybar/scripts

    bind = , xf86audioraisevolume, exec, $SCRIPT/volume -si 5
    bind = , xf86audiolowervolume, exec, $SCRIPT/volume -sd 5
    bind = , xf86AudioMicMute, exec, $SCRIPT/volume -mm
    bind = , xf86audioMute, exec, $SCRIPT/volume -sm

    bind = , xf86audioNext, exec, $SCRIPT/media-control --next
    bind = , xf86audioPrev, exec, $SCRIPT/media-control --prev
    bind = , xf86audioPlay, exec, $SCRIPT/media-control --play-pause

    bind = , xf86KbdBrightnessDown, exec, $SCRIPT/kb-brightness --dec
    bind = , xf86KbdBrightnessUp, exec, $SCRIPT/kb-brightness --inc

    bind = , xf86MonBrightnessDown, exec, $SCRIPT/brightness --dec
    bind = , xf86MonBrightnessUp, exec, $SCRIPT/brightness --inc
  '';

  home.file.".config/hypr/env_var.conf".text = ''
    # Environment Variables
    # see https://wiki.hyprland.org/Configuring/Environment-variables/

    # Theming Related Variables
    # Set cursor size. See FAQ below for why you might want this variable set.
    # https://wiki.hyprland.org/FAQ/
    env = XCURSOR_SIZE,24

    # Set a GTK theme manually, for those who want to avoid appearance tools such as lxappearance or nwg-look
    #env = GTK_THEME,

    # Set your cursor theme. The theme needs to be installed and readable by your user.
    #env = XCURSOR_THEME,

    # the line below may help with multiple monitors
    #env = WLR_EGL_NO_MODIFIERS,1

    #XDG Specifications
    env = XDG_CURRENT_DESKTOP,Hyprland
    env = XDG_SESSION_TYPE,wayland
    env = XDG_SESSION_DESKTOP,Hyprland

    # Toolkit Backend Variables

    # GTK: Use wayland if available, fall back to x11 if not.
    #env = GDK_BACKEND,wayland,x11

    # QT: Use wayland if available, fall back to x11 if not.
    #env = QT_QPA_PLATFORM,wayland,xcb

    # Run SDL2 applications on Wayland. Remove or set to x11 if games that
    # provide older versions of SDL cause compatibility issues
    #env = SDL_VIDEODRIVER,wayland

    # Clutter package already has wayland enabled, this variable
    #will force Clutter applications to try and use the Wayland backend
    #env = CLUTTER_BACKEND,wayland

    # QT Variables

    # (From the QT documentation) enables automatic scaling, based on the monitor’s pixel density
    # https://doc.qt.io/qt-5/highdpi.html
    #env = QT_AUTO_SCREEN_SCALE_FACTOR,1

    # Tell QT applications to use the Wayland backend, and fall back to x11 if Wayland is unavailable
    #env = QT_QPA_PLATFORM,wayland,xcb

    # Disables window decorations on QT applications
    #env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1

    #Tells QT based applications to pick your theme from qt5ct, use with Kvantum.
    #env = QT_QPA_PLATFORMTHEME,qt5ct
  '';
}
