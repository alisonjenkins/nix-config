{ pkgs, inputs, system, config, ... }: {
  home.packages =  if pkgs.stdenv.isLinux then [
    inputs.quickshell.packages.${system}.default
    pkgs.fuzzel
    pkgs.mako
    pkgs.nautilus
    pkgs.swaybg
    pkgs.swaylock
    pkgs.swww
    pkgs.unstable.wlr-which-key
    pkgs.waybar
    pkgs.xwayland-satellite
  ] else [];

  programs.niri.settings = {
    clipboard.disable-primary = true;
    cursor.hide-when-typing = true;
    hotkey-overlay.skip-at-startup = true;
    prefer-no-csd = true;
    screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

    binds = with config.lib.niri.actions; {
      "Alt+Print".action = screenshot-window;
      "Ctrl+Alt+Delete".action = quit;
      "Ctrl+Print".action = screenshot;
      "Mod+1".action = focus-workspace "chat";
      "Mod+2".action = focus-workspace "terminal";
      "Mod+3".action = focus-workspace "browser";
      "Mod+4".action = focus-workspace "game";
      "Mod+5".action = focus-workspace "gaming";
      "Mod+6".action = focus-workspace "obsidian";
      "Mod+7".action = focus-workspace "passwordmanager";
      "Mod+8".action = focus-workspace 8;
      "Mod+9".action = focus-workspace 9;
      "Mod+BracketLeft".action = consume-or-expel-window-left;
      "Mod+BracketRight".action = consume-or-expel-window-right;
      "Mod+C".action = center-column;
      "Mod+Comma".action = consume-window-into-column;
      "Mod+Ctrl+1".action.move-column-to-workspace = "chat";
      "Mod+Ctrl+2".action.move-column-to-workspace = "terminal";
      "Mod+Ctrl+3".action.move-column-to-workspace = "browser";
      "Mod+Ctrl+4".action.move-column-to-workspace = "game";
      "Mod+Ctrl+5".action.move-column-to-workspace = "gaming";
      "Mod+Ctrl+6".action.move-column-to-workspace = "obsidian";
      "Mod+Ctrl+7".action.move-column-to-workspace = "passwordmanager";
      "Mod+Ctrl+8".action.move-column-to-workspace = 8;
      "Mod+Ctrl+9".action.move-column-to-workspace = 9;
      "Mod+Ctrl+C".action = center-visible-columns;
      "Mod+Ctrl+Down".action = move-window-down;
      "Mod+Ctrl+End".action = move-column-to-last;
      "Mod+Ctrl+F".action = expand-column-to-available-width;
      "Mod+Ctrl+H".action = move-column-left;
      "Mod+Ctrl+Home".action = move-column-to-first;
      "Mod+Ctrl+I".action = move-column-to-workspace-up;
      "Mod+Ctrl+J".action = move-window-down;
      "Mod+Ctrl+K".action = move-window-up;
      "Mod+Ctrl+L".action = move-column-right;
      "Mod+Ctrl+Left".action = move-column-left;
      "Mod+Ctrl+Page_Down".action = move-column-to-workspace-down;
      "Mod+Ctrl+Page_Up".action = move-column-to-workspace-up;
      "Mod+Ctrl+R".action = reset-window-height;
      "Mod+Ctrl+Right".action = move-column-right;
      "Mod+Ctrl+Shift+F".action = toggle-windowed-fullscreen;
      "Mod+Ctrl+Shift+WheelScrollDown".action = move-column-right;
      "Mod+Ctrl+Shift+WheelScrollUp".action = move-column-left;
      "Mod+Ctrl+U".action = move-column-to-workspace-down;
      "Mod+Ctrl+Up".action = move-window-up;
      "Mod+Ctrl+WheelScrollLeft".action = move-column-left;
      "Mod+Ctrl+WheelScrollRight".action = move-column-right;
      "Mod+End".action = focus-column-last;
      "Mod+Equal".action = set-column-width "+10%";
      "Mod+F".action = maximize-column;
      "Mod+Home".action = focus-column-first;
      "Mod+I".action = focus-workspace-up;
      "Mod+Minus".action = set-column-width "-10%";
      "Mod+Page_Down".action = focus-workspace-down;
      "Mod+Page_Up".action = focus-workspace-up;
      "Mod+Period".action = expel-window-from-column;
      "Mod+R".action = switch-preset-column-width;
      "Mod+Shift+Ctrl+Down".action = move-column-to-monitor-down;
      "Mod+Shift+Ctrl+H".action = move-column-to-monitor-left;
      "Mod+Shift+Ctrl+J".action = move-column-to-monitor-down;
      "Mod+Shift+Ctrl+K".action = move-column-to-monitor-up;
      "Mod+Shift+Ctrl+L".action = move-column-to-monitor-right;
      "Mod+Shift+Ctrl+Left".action = move-column-to-monitor-left;
      "Mod+Shift+Ctrl+Right".action = move-column-to-monitor-right;
      "Mod+Shift+Ctrl+Up".action = move-column-to-monitor-up;
      "Mod+Shift+Down".action = focus-monitor-down;
      "Mod+Shift+E".action = quit;
      "Mod+Shift+Equal".action = set-window-height "+10%";
      "Mod+Shift+F".action = fullscreen-window;
      "Mod+Shift+H".action = focus-monitor-left;
      "Mod+Shift+I".action = move-workspace-up;
      "Mod+Shift+J".action = focus-monitor-down;
      "Mod+Shift+K".action = focus-monitor-up;
      "Mod+Shift+L".action = focus-monitor-right;
      "Mod+Shift+Left".action = focus-monitor-left;
      "Mod+Shift+Minus".action = set-window-height "-10%";
      "Mod+Shift+P".action = power-off-monitors;
      "Mod+Shift+Page_Down".action = move-workspace-down;
      "Mod+Shift+Page_Up".action = move-workspace-up;
      "Mod+Shift+R".action = switch-preset-window-height;
      "Mod+Shift+Right".action = focus-monitor-right;
      "Mod+Shift+Slash".action = show-hotkey-overlay;
      "Mod+Shift+U".action = move-workspace-down;
      "Mod+Shift+Up".action = focus-monitor-up;
      "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;
      "Mod+Shift+WheelScrollDown".action = focus-column-right;
      "Mod+Shift+WheelScrollUp".action = focus-column-left;
      "Mod+U".action = focus-workspace-down;
      "Mod+V".action = toggle-window-floating;
      "Mod+W".action = toggle-column-tabbed-display;
      "Mod+WheelScrollLeft".action = focus-column-left;
      "Mod+WheelScrollRight".action = focus-column-right;
      "Print".action = screenshot;

      "Mod+T" = {
        action.spawn  = ["ghostty"];
        hotkey-overlay.title="Open a Terminal: ghostty";
      };

      "Mod+D" = {
        action.spawn = ["fuzzel"];
        hotkey-overlay.title="Run an Application: fuzzel";
      };

      "Super+Alt+L" = {
        action.spawn = "swaylock";
        hotkey-overlay.title="Lock the Screen: swaylock";
      };

      "XF86AudioRaiseVolume" = {
        allow-when-locked = true;
        action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+"];
      };

      "XF86AudioLowerVolume" = {
        allow-when-locked = true;
        action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-"];
      };

      "XF86AudioMute" = {
        allow-when-locked = true;
        action.spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"];
      };

      "XF86AudioMicMute" = {
        allow-when-locked = true;
        action.spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"];
      };

      "XF86AudioPlay" = {
        action.spawn = ["playerctl" "play-pause"];
      };

      "XF86AudioPause" = {
        action.spawn = ["playerctl" "play-pause"];
      };

      "XF86AudioNext" = {
        action.spawn = ["playerctl" "next"];
      };

      "XF86AudioPrev" = {
        action.spawn = ["playerctl" "previous"];
      };

      "XF86AudioStop" = {
        action.spawn = ["playerctl" "stop"];
      };

      "Mod+O" = {
        repeat = false;
        action = toggle-overview;
      };

      "Mod+Q" = {
        action = close-window;
      };

      "Mod+Left" = {
        action = focus-column-left;
      };

      "Mod+Right" = {
        action = focus-column-right;
      };

      "Mod+Up" = {
        action = focus-window-up;
      };

      "Mod+Down" = {
        action = focus-window-down;
      };

      "Mod+H" = {
        action = focus-column-left;
      };

      "Mod+L" = {
        action = focus-column-right;
      };

      "Mod+J" = {
        action = focus-window-down;
      };

      "Mod+K" = {
        action = focus-window-up;
      };

      "Mod+WheelScrollDown" = {
        cooldown-ms=150;
        action = focus-workspace-down;
      };

      "Mod+WheelScrollUp" = {
        cooldown-ms=150;
        action = focus-workspace-up;
      };

      "Mod+Ctrl+WheelScrollDown" = {
        cooldown-ms=150;
        action = move-column-to-workspace-down;
      };

      "Mod+Ctrl+WheelScrollUp" = {
        cooldown-ms=150;
        action = move-column-to-workspace-up;
      };

      "Mod+Space" = {
        hotkey-overlay.title="Chorded menu";
        action.spawn = ["wlr-which-key"];
      };

      "Mod+Escape" = {
        allow-inhibiting=false;
        action = toggle-keyboard-shortcuts-inhibit;
      };
    };

    environment = {
      DISPLAY  = ":0";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };

    input = {
      workspace-auto-back-and-forth = true;

      warp-mouse-to-focus = {
        enable = true;
      };

      keyboard = {
        numlock = true;

        xkb = {
          layout = "us";
          options = "ctrl:nocaps";
        };
      };

      touchpad = {
        middle-emulation = true;
        tap = true;
      };
    };

    layout = {
      center-focused-column = "never";
      gaps = 16;

      default-column-width = {
        proportion = 0.5;
      };

      preset-column-widths = [
        { proportion = 1. / 3.; }
        { proportion = 1. / 2.; }
        { proportion = 2. / 3.; }
      ];

      focus-ring = {
        width = 4;
      };

      border = {
        enable = false;
      };

      shadow = {
        color = "#0007";
        softness = 30;
        spread = 5;

        offset = {
          x = 0;
          y = 5;
        };
      };
    };

    layer-rules = [
      {
        place-within-backdrop = true;

        matches = [
          {
            namespace = "^wallpaper$";
          }
        ];
      }
    ];

    spawn-at-startup = [
      { command = ["dbus-update-activation-environment" "--systemd" "WAYLAND_DISPLAY" "XDG_CURRENT_DESKTOP"]; }
      { command = ["xwayland-satellite"]; }
      { command = ["1password"]; }
      { command = ["mako"]; }
      { command = ["swww-daemon"]; }
      { command = ["waybar"]; }
      { command = ["swaybg" "-i" "~/Pictures/Wallpapers/1325118.png"]; }
    ];

    switch-events = {
      lid-close = {
        action.spawn = ["niri" "msg" "output" "eDP-2" "off"];
      };
      lid-open = {
        action.spawn = ["niri" "msg" "output" "eDP-2" "on"];
      };
    };

    window-rules = [
      {
        open-focused = false;

        default-floating-position = {
          x = 10;
          y = 10;
          relative-to = "bottom-right";
        };

        matches = [
          {
            app-id = "steam";
            title = "^notificationtoasts_\d+_desktop$";
          }
        ];
      }

      {
        block-out-from = "screen-capture";
        open-focused = true;
        open-maximized = true;
        open-on-workspace = "passwordmanager";

        matches = [
          {
            app-id = "1Password";
          }
          {
            app-id = "^org\.gnome\.World\.Secrets$";
          }
          {
            app-id = "^org\.keepassxc\.KeePassXC$";
          }
          # {
          #   app-id = "1Password";
          #   title = "^Lock Screen — 1Password$";
          # }
        ];
      }

      {
        baba-is-float = true;
        block-out-from = "screen-capture";
        open-floating = true;
        open-focused = true;

        excludes = [
          {
            app-id = "1Password";
            title = "^Lock Screen — 1Password$";
          }
        ];

        matches = [
          {
            app-id="org.kde.ksecretd";
            title="^KDE Wallet Service$";
          }
          {
            app-id="1Password";
            title="^1Password$";
          }
          {
            app-id="gay\.vaskel\.Soteria";
          }
        ];
      }

      {
        open-floating = true;

        matches = [
          {
            app-id = "^firefox$";
            title = "^Picture-in-Picture$";
          }
        ];
      }

      {
        default-column-display = "tabbed";
        open-maximized = true;
        open-on-workspace = "chat";

        matches = [
          {
            app-id = "^Keybase$";
          }
          {
            app-id = "^vesktop$";
          }
          {
            app-id = "^com\.ktechpit\.whatsie$";
          }
        ];
      }

      {
        open-fullscreen = true;
        open-on-workspace = "terminal";
        draw-border-with-background = false;
        opacity = 0.9;

        border = {
          enable = false;
        };

        focus-ring = {
          enable = true;
        };

        matches = [
          {
            app-id = "Alacritty";
          }
          {
            app-id = "com.mitchellh.ghostty";
          }
        ];
      }

      {
        open-maximized = true;
        open-on-workspace = "browser";

        matches = [
          {
            app-id = "firefox";
          }
        ];
      }

      {
        open-maximized = true;
        open-on-workspace = "obsidian";

        matches = [
          {
            app-id = "^obsidian$";
          }
        ];
      }

      {
        open-on-workspace = "gaming";

        matches = [
          {
            app-id = "^org.prismlauncher.PrismLauncher$";
          }
          {
            app-id = "^steam$";
          }
        ];
      }

      {
        open-fullscreen = true;
        open-on-workspace = "game";

        matches = [
          {
            app-id= "^gamescope$";
          }
        ];
      }
    ];

    workspaces = {
      "01-chat".name = "chat";
      "02-terminal".name = "terminal";
      "03-browser".name = "browser";
      "04-game".name = "game";
      "05-gaming".name = "gaming";
      "06-obsidian".name = "obsidian";
      "07-passwordmanager".name = "passwordmanager";
    };
  };

  home.file = {
    # ".config/niri/config.kdl".source = ./config.kdl;
    ".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
  };
}
