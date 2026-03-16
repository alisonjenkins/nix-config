{ config, lib, pkgs, ... }:
let
  cfg = config.custom.niri;
  micMuteSpawn = lib.concatMapStringsSep " " (s: ''"${s}"'') cfg.micMuteCommand;
in {
  options.custom.niri = {
    enable = lib.mkEnableOption "niri window manager configuration";

    micMuteCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ];
      description = "Command to run when XF86AudioMicMute is pressed.";
    };

    extraBinds = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional KDL bind entries appended inside the binds block.";
    };

    extraWindowRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional KDL window-rule blocks appended after the built-in rules.";
    };

    extraSpawnAtStartup = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional spawn-at-startup lines.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."niri/config.kdl".text = ''
      clipboard {
          disable-primary
      }

      cursor {
          hide-when-typing
      }

      hotkey-overlay {
          skip-at-startup
      }

      prefer-no-csd

      screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

      environment {
          ELECTRON_OZONE_PLATFORM_HINT "auto"
          QT_QPA_PLATFORMTHEME "gtk3"
          GTK_THEME "Adwaita:dark"
          XCURSOR_THEME "Adwaita"
          XCURSOR_SIZE "24"
      }

      input {
          workspace-auto-back-and-forth
          warp-mouse-to-focus

          keyboard {
              numlock

              xkb {
                  layout "us"
                  options "ctrl:nocaps"
              }
          }

          touchpad {
              middle-emulation
              tap
          }
      }

      layout {
          center-focused-column "never"
          gaps 16

          default-column-width {
              proportion 0.5
          }

          preset-column-widths {
              proportion 0.33333
              proportion 0.5
              proportion 0.66667
          }

          focus-ring {
              width 4
          }

          border {
              off
          }

          shadow {
              color "#0007"
              softness 30
              spread 5
              offset x=0 y=5
          }
      }

      layer-rule {
          match namespace="^wallpaper$"
          place-within-backdrop true
      }

      spawn-at-startup "systemctl" "--user" "import-environment" "DISPLAY" "GTK_THEME" "QT_QPA_PLATFORMTHEME" "WAYLAND_DISPLAY" "XCURSOR_SIZE" "XCURSOR_THEME" "XDG_CURRENT_DESKTOP"
      spawn-at-startup "dbus-update-activation-environment" "--all" "--systemd"
      spawn-at-startup "systemctl" "--user" "restart" "xdg-desktop-portal.service"
      spawn-at-startup "noctalia-shell"
      spawn-at-startup "1password" "--silent"
      spawn-at-startup "zen-beta"
      spawn-at-startup "niri" "msg" "action" "focus-workspace" "terminal"
      ${cfg.extraSpawnAtStartup}

      switch-events {
          lid-close { spawn "niri" "msg" "output" "eDP-2" "off"; }
          lid-open { spawn "niri" "msg" "output" "eDP-2" "on"; }
      }

      workspace "chat"
      workspace "terminal"
      workspace "browser"
      workspace "game"
      workspace "gaming"
      workspace "obsidian"
      workspace "passwordmanager"

      // Window rules
      window-rule {
          match app-id="steam" title="^notificationtoasts_\\d+_desktop$"
          open-focused false
          default-floating-position x=10 y=10 relative-to="bottom-right"
      }

      window-rule {
          match app-id="1password"
          match app-id="^org\\.gnome\\.World\\.Secrets$"
          match app-id="^org\\.keepassxc\\.KeePassXC$"
          block-out-from "screen-capture"
          open-focused true
          open-maximized true
          open-on-workspace "passwordmanager"
      }

      window-rule {
          match app-id="org.kde.ksecretd" title="^KDE Wallet Service$"
          match app-id="gay\\.vaskel\\.Soteria"
          baba-is-float true
          block-out-from "screen-capture"
          open-floating true
          open-focused true
      }

      window-rule {
          match app-id="^firefox$" title="^Picture-in-Picture$"
          open-floating true
      }

      window-rule {
          match app-id="^Keybase$"
          match app-id="^discord-canary$"
          match app-id="^vesktop$"
          match app-id="^ZapZap$"
          match app-id="^signal$"
          default-column-display "tabbed"
          open-focused false
          open-maximized true
          open-on-workspace "chat"
      }

      window-rule {
          match app-id="Alacritty"
          match app-id="com.mitchellh.ghostty"
          draw-border-with-background false
          opacity 0.9
          open-fullscreen false
          open-maximized true
          open-on-workspace "terminal"
          border {
              off
          }
          focus-ring {
              on
          }
      }

      window-rule {
          match app-id="firefox"
          match app-id="zen"
          open-maximized true
          open-on-workspace "browser"
      }

      window-rule {
          match app-id="^obsidian$"
          open-maximized true
          open-on-workspace "obsidian"
      }

      window-rule {
          exclude app-id="^steam$" title="^Steam Big Picture Mode$"
          match app-id="^org.prismlauncher.PrismLauncher$"
          match app-id="^steam$"
          match app-id="^heroic$"
          open-on-workspace "gaming"
          open-maximized true
      }

      window-rule {
          match app-id="^gamescope$"
          match app-id="^steam$" title="^Steam Big Picture Mode$"
          match app-id="^steam_app_.*$"
          match app-id="^steam_proton$"
          open-fullscreen true
          open-focused true
          open-on-workspace "game"
      }

      window-rule {
          match app-id="^xwaylandvideobridge$"
          match title="^Xwayland Video Bridge"
          open-floating true
          open-focused false
          opacity 0.0
      }

      ${cfg.extraWindowRules}

      binds {
          // Screenshots
          Alt+Print { screenshot-window; }
          Ctrl+Alt+Delete { quit; }
          Ctrl+Print { screenshot; }
          Print { screenshot; }

          // Workspace focus
          Mod+1 { focus-workspace "chat"; }
          Mod+2 { focus-workspace "terminal"; }
          Mod+3 { focus-workspace "browser"; }
          Mod+4 { focus-workspace "game"; }
          Mod+5 { focus-workspace "gaming"; }
          Mod+6 { focus-workspace "obsidian"; }
          Mod+7 { focus-workspace "passwordmanager"; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }

          // Column/window management
          Mod+BracketLeft { consume-or-expel-window-left; }
          Mod+BracketRight { consume-or-expel-window-right; }
          Mod+C { center-column; }
          Mod+Comma { consume-window-into-column; }
          Mod+Period { expel-window-from-column; }
          Mod+R { switch-preset-column-width; }
          Mod+F { maximize-column; }
          Mod+W { toggle-column-tabbed-display; }
          Mod+V { toggle-window-floating; }

          // Move column to workspace
          Mod+Ctrl+1 { move-column-to-workspace "chat"; }
          Mod+Ctrl+2 { move-column-to-workspace "terminal"; }
          Mod+Ctrl+3 { move-column-to-workspace "browser"; }
          Mod+Ctrl+4 { move-column-to-workspace "game"; }
          Mod+Ctrl+5 { move-column-to-workspace "gaming"; }
          Mod+Ctrl+6 { move-column-to-workspace "obsidian"; }
          Mod+Ctrl+7 { move-column-to-workspace "passwordmanager"; }
          Mod+Ctrl+8 { move-column-to-workspace 8; }
          Mod+Ctrl+9 { move-column-to-workspace 9; }

          Mod+Ctrl+C { center-visible-columns; }
          Mod+Ctrl+F { expand-column-to-available-width; }
          Mod+Ctrl+R { reset-window-height; }
          Mod+Ctrl+Shift+F { toggle-windowed-fullscreen; }

          // Move column/window directional
          Mod+Ctrl+Down { move-window-down; }
          Mod+Ctrl+Up { move-window-up; }
          Mod+Ctrl+H { move-column-left; }
          Mod+Ctrl+J { move-window-down; }
          Mod+Ctrl+K { move-window-up; }
          Mod+Ctrl+L { move-column-right; }
          Mod+Ctrl+Left { move-column-left; }
          Mod+Ctrl+Right { move-column-right; }
          Mod+Ctrl+Home { move-column-to-first; }
          Mod+Ctrl+End { move-column-to-last; }

          // Move column to workspace up/down
          Mod+Ctrl+I { move-column-to-workspace-up; }
          Mod+Ctrl+U { move-column-to-workspace-down; }
          Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
          Mod+Ctrl+Page_Up { move-column-to-workspace-up; }

          // Scroll-based column movement
          Mod+Ctrl+Shift+WheelScrollDown { move-column-right; }
          Mod+Ctrl+Shift+WheelScrollUp { move-column-left; }
          Mod+Ctrl+WheelScrollLeft { move-column-left; }
          Mod+Ctrl+WheelScrollRight { move-column-right; }

          // Focus navigation
          Mod+Home { focus-column-first; }
          Mod+End { focus-column-last; }
          Mod+I { focus-workspace-up; }
          Mod+U { focus-workspace-down; }
          Mod+Page_Down { focus-workspace-down; }
          Mod+Page_Up { focus-workspace-up; }

          // Resize
          Mod+Equal { set-column-width "+10%"; }
          Mod+Minus { set-column-width "-10%"; }
          Mod+Shift+Equal { set-window-height "+10%"; }
          Mod+Shift+Minus { set-window-height "-10%"; }

          // Fullscreen & floating
          Mod+Shift+F { fullscreen-window; }
          Mod+Shift+V { switch-focus-between-floating-and-tiling; }

          // Monitor focus
          Mod+Shift+Down { focus-monitor-down; }
          Mod+Shift+H { focus-monitor-left; }
          Mod+Shift+J { focus-monitor-down; }
          Mod+Shift+K { focus-monitor-up; }
          Mod+Shift+L { focus-monitor-right; }
          Mod+Shift+Left { focus-monitor-left; }
          Mod+Shift+Right { focus-monitor-right; }
          Mod+Shift+Up { focus-monitor-up; }

          // Move column to monitor
          Mod+Shift+Ctrl+Down { move-column-to-monitor-down; }
          Mod+Shift+Ctrl+H { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+J { move-column-to-monitor-down; }
          Mod+Shift+Ctrl+K { move-column-to-monitor-up; }
          Mod+Shift+Ctrl+L { move-column-to-monitor-right; }
          Mod+Shift+Ctrl+Left { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
          Mod+Shift+Ctrl+Up { move-column-to-monitor-up; }

          // Misc
          Mod+Shift+E { quit; }
          Mod+Shift+P { power-off-monitors; }
          Mod+Shift+I { move-workspace-up; }
          Mod+Shift+U { move-workspace-down; }
          Mod+Shift+Page_Down { move-workspace-down; }
          Mod+Shift+Page_Up { move-workspace-up; }
          Mod+Shift+R { switch-preset-window-height; }
          Mod+Shift+Slash { show-hotkey-overlay; }

          // Scroll-based focus
          Mod+Shift+WheelScrollDown { focus-column-right; }
          Mod+Shift+WheelScrollUp { focus-column-left; }
          Mod+WheelScrollLeft { focus-column-left; }
          Mod+WheelScrollRight { focus-column-right; }

          // Spawn commands
          Mod+T { spawn "ghostty"; }
          Mod+D { spawn "tofi-drun"; }
          Super+Alt+L { spawn "lock-session"; }

          // Audio
          XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+"; }
          XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-"; }
          XF86AudioMute allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
          XF86AudioMicMute allow-when-locked=true { spawn ${micMuteSpawn}; }

          // Media
          XF86AudioPlay { spawn "playerctl" "play-pause"; }
          XF86AudioPause { spawn "playerctl" "play-pause"; }
          XF86AudioNext { spawn "playerctl" "next"; }
          XF86AudioPrev { spawn "playerctl" "previous"; }
          XF86AudioStop { spawn "playerctl" "stop"; }

          // Overview
          Mod+O repeat=false { toggle-overview; }

          // Close window
          Mod+Q { close-window; }

          // Directional focus
          Mod+Left { focus-column-left; }
          Mod+Right { focus-column-right; }
          Mod+Up { focus-window-up; }
          Mod+Down { focus-window-down; }
          Mod+H { focus-column-left; }
          Mod+L { focus-column-right; }
          Mod+J { focus-window-down; }
          Mod+K { focus-window-up; }

          // Cooldown scroll
          Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
          Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }
          Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
          Mod+Ctrl+WheelScrollUp cooldown-ms=150 { move-column-to-workspace-up; }

          // Which-key
          Mod+Space { spawn "wlr-which-key"; }

          // Escape inhibit
          Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }

          ${cfg.extraBinds}
      }
    '';
  };
}
