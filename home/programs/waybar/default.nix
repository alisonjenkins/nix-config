{ pkgs, ... }: {
  home.packages =
    if pkgs.stdenv.isLinux
    then
      with pkgs; [
        brightnessctl
        cpupower-gui
        hyprshade
        playerctl
        swww
      ]
    else [ ];

  programs.waybar = {
    enable =
      if pkgs.stdenv.isLinux
      then true
      else false;
    package = pkgs.waybar;
    style = ./style.css;

    settings = [
      {
        layer = "top";
        position = "top";
        height = 46;
        spacing = 0;
        margin-top = 0;
        margin-left = 10;
        margin-right = 10;

        modules-left = [
          "custom/launcher"
          "cpu"
          "custom/gpu"
          "memory"
          "temperature"
          "disk"
          "network"
        ];

        modules-center = [
          "hyprland/workspaces"
          "hyprland/window"
        ];

        modules-right = [
          "pulseaudio"
          "backlight"
          "upower"
          "custom/notifications"
          "tray"
          "clock"
          "custom/power"
        ];

        backlight = {
          format = "{icon} {percent}%";
          interval = 2;
          format-icons = [ "󰹇" "󰃜" "󰃛" "󰃝" "󰃟" "󰃠" ];
          states = {
            normal = 0;
            warning = 80;
            critical = 9;
          };
          on-click = "hyprshade toggle bluefilter";
          on-click-right = "hyprshade toggle extradark";
          on-scroll-down = "brightnessctl -q set 5%-";
          on-scroll-up = "brightnessctl -q set 5%+";
          tooltip = false;
        };

        clock = {
          format = "󰥔 {:%H:%M 󰃭 %d %b %Y}";
          format-alt = " {:%I:%M %p  %a %d}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            on-click-right = "mode";
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'><b>{}</b></span>";
              weeks = "<span color='#99ffdd'><b>W{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
          actions = {
            on-click-right = "mode";
            on-click-forward = "tz_up";
            on-click-backward = "tz_down";
            on-scroll-up = "shift_up";
            on-scroll-down = "shift_down";
          };
        };

        cpu = {
          interval = 1;
          format = "󰌢 {load}";
          tooltip = false;
          on-click = "missioncenter";
          on-click-right = "kitty --class wm-floating --title all_is_kitty --hold --detach sh -c 'htop'";
        };

        "custom/gpu" = {
          interval = 1;
          # exec = "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits";
          format = "󰢮 {}%";
          return-type = "";
          on-click = "missioncenter";
        };

        "custom/launcher" = {
          format = "{}";
          tooltip = true;
          exec = "echo '{\"text\":\"💧\",\"tooltip\":\"Drun | Run\"}'";
          return-type = "json";
          on-click = "wofi --show drun";
        };

        "custom/notifications" = {
          tooltip = false;
          format = "{icon}";
          format-icons = {
            notification = " <span foreground='red'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            dnd-none = "";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "custom/power" = {
          format = "{}";
          exec = "echo '{\"text\":\"⏻\",\"tooltip\":\"Power\"}'";
          return-type = "json";
          on-click = "${pkgs.wleave}/bin/wleave";
        };

        disk = {
          format = " {free}";
          format-alt = " {percentage_used}% ({free})";
          tooltip = true;
          interval = 10;
        };

        "hyprland/window" = {
          format = "  {}";
          separate-outputs = true;
          max-length = 32;
          rewrite = {
            "(.*)fish" = "> [$1]";
            "(.*)neovide" = "neovide 󰕷 ";
            "(.*)Mozilla Firefox" = "Firefox 󰈹";
            "(.*)BlueMail" = "BlueMail 󰊫 ";
            "(.*)Visual Studio Code" = "Code 󰨞";
            "(.*)Dolphin" = "$1 󰉋";
            "(.*)Spotify" = "Spotify 󰓇";
            "(.*)Steam" = "Steam 󰓓";
          };
        };

        "hyprland/workspaces" = {
          active-only = false;
          disable-scroll = false;
          format = "{icon} {id} {name}";
          on-scroll-down = "hyprctl dispatch workspace +1";
          on-scroll-up = "hyprctl dispatch workspace -1";
          sort-by-number = true;

          format-icons = {
            urgent = "󰗖";
            active = "󰝥";
            default = "󰝦";
          };

          persistent-workspaces = {
            "*" = 5;
          };
        };

        memory = {
          interval = 2;
          format = "󰾅 {used}GB";
          max-length = 30;
          tooltip = true;
          tooltip-format = " {used:0.1f}GB/{total:0.1f}GB";
          on-click = "missioncenter";
          on-click-right = "kitty --start-as=fullscreen --title all_is_kitty sh -c 'btop'";
        };

        network = {
          format = "󰹹{bandwidthTotalBytes}";
          format-disconnected = "No Internet⚡";
          format-linked = "{ifname} (No IP) ‼️";
          format-alt = " {bandwidthUpBytes} |  {bandwidthDownBytes}";
          format-wifi = "{essid}({signalStrength}%) 󰖩 ";
          format-ethernet = "🌐 {ipaddr}/{cidr} ";
          tooltip-format-wifi = "󰖩  {essid}({signalStrength}%)";
          tooltip-format-ethernet = "🌐 {ipaddr}/{cidr}";
          tooltip-format-disconnected = "󰖪 ";
          on-click-right = "nm-connection-editor";
          interval = 2;
        };

        pulseaudio = {
          format = "{icon} {volume}";
          format-bluetooth = "{icon}  {volume}%";
          format-bluetooth-muted = "󰝟 {icon}";
          format-muted = "婢 {volume}";
          tooltip-format = "{icon} {desc} // {volume}%";
          scroll-step = 5;
          "format-icons" = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [ "" "" "" ];
          };
          on-click = "pavucontrol";
        };

        temperature = {
          interval = 2;
          format = "{temperatureC}°C ";
          format-icons = [ "" "" "" "" "" ];
        };

        tray = {
          icon-size = 15;
          spacing = 15;
        };

        upower = {
          icon-size = 18;
          hide-if-empty = true;
          tooltip = false;
          tooltip-spacing = 20;
          tooltip-padding = 8;
          on-click = "cpupower-gui";
        };
      }
    ];
  };
}
