{ config, lib, pkgs, ... }:

let
  cfg = config.modules.desktop;
  plymouth = lib.getExe' config.boot.plymouth.package "plymouth";
in
{
  options.modules.desktop.flickerFreeBoot.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Plymouth boot splash, retained on the framebuffer until the display manager takes over.";
  };

  config = lib.mkIf (cfg.enable && cfg.flickerFreeBoot.enable) {
    boot = {
      plymouth.enable = true;

      # loglevel comes from boot.consoleLogLevel (base).
      kernelParams = [
        "splash"
        "systemd.show_status=false"
        "vt.global_cursor_default=0"
      ];
    };

    systemd.services.plymouth-quit.serviceConfig = {
      # Clear VT1 while Plymouth still holds DRM master so the clear is invisible.
      ExecStartPre = "-${pkgs.bash}/bin/bash -c 'echo -ne \"\\033[2J\\033[H\" > /dev/tty1'";

      ExecStart = [
        ""
        "-${plymouth} quit --retain-splash"
      ];
    };
  };
}
