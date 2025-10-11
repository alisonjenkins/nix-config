{pkgs, ...}: {
  home.packages = with pkgs; [
    bluez
    brightnessctl
    hypridle
    playerctl
  ];

  services.hypridle = {
    enable = true;
    package = pkgs.unstable.hypridle;

    settings = {
      general = let
        suspendScript = pkgs.writeShellScriptBin "hypridle-suspend" ''
          playerctl pause
        '';

        resumeScript = pkgs.writeShellScriptBin "hypridle-resume" ''
          niri msg action power-on-monitors
          bluetoothctl connect '88:C9:E8:06:5E:9C' && playerctl play
        '';

      in {
        after_sleep_cmd = "${resumeScript}/bin/hypridle-resume";
        before_sleep_cmd = "${suspendScript}/bin/hypridle-suspend";
        inhibit_sleep = 3;
        lock_cmd = "${pkgs.lock-session}/bin/lock-session";
      };

      listener = [
        {
          timeout = 150;
          on-timeout = "brightnessctl -sd rgb:kbd_backlight set 0";
          on-resume = "brightnessctl -rd rgb:kbd_backlight";
        }
        {
          timeout = 900;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 930;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1200;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

}
