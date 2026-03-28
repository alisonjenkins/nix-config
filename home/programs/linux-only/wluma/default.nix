{ pkgs, lib, config, ... }:

let
  cfg = config.programs.wluma;
in
{
  options.programs.wluma = {
    enable = lib.mkEnableOption "wluma ALS-based automatic brightness adjustment";

    alsDevicePath = lib.mkOption {
      type = lib.types.str;
      default = "/sys/bus/iio/devices/iio:device0";
      description = "Path to the ambient light sensor IIO device.";
    };

    backlightPath = lib.mkOption {
      type = lib.types.str;
      default = "/sys/class/backlight/amdgpu_bl2";
      description = "Path to the backlight device.";
    };

    outputName = lib.mkOption {
      type = lib.types.str;
      default = "eDP-1";
      description = "Wayland output name for the internal display.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.wluma ];

    xdg.configFile."wluma/config.toml".source = pkgs.writeText "wluma-config.toml" ''
      [als.iio]
      path = "${cfg.alsDevicePath}"
      thresholds = { 0 = "night", 20 = "dark", 80 = "dim", 250 = "normal", 500 = "bright", 800 = "outdoors" }

      [[output.backlight]]
      name = "${cfg.outputName}"
      path = "${cfg.backlightPath}"
      capturer = "none"
    '';

    systemd.user.services.wluma = {
      Unit = {
        Description = "Automatic brightness adjustment based on ambient light";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wluma}/bin/wluma";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
