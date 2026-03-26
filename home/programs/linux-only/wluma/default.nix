{ pkgs, lib, autoBrightness ? null, ... }:

let
  enabled = autoBrightness != null && autoBrightness.enable or false;

  configToml = pkgs.writeText "wluma-config.toml" ''
    [als.iio]
    path = "${autoBrightness.alsDevicePath}"
    thresholds = { 0 = "night", 20 = "dark", 80 = "dim", 250 = "normal", 500 = "bright", 800 = "outdoors" }

    [[output.backlight]]
    name = "${autoBrightness.outputName}"
    path = "${autoBrightness.backlightPath}"
    capturer = "none"
  '';
in
lib.mkIf enabled {
  home.packages = [ pkgs.wluma ];

  xdg.configFile."wluma/config.toml".source = configToml;

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
}
