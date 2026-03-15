{ config, lib, pkgs, ... }:
let
  cfg = config.modules.plymouth;
  plymouth = lib.getExe' config.boot.plymouth.package "plymouth";
in
{
  options.modules.plymouth = {
    enable = lib.mkEnableOption "Plymouth boot splash with flicker-free boot";
  };

  config = lib.mkIf cfg.enable {
    boot = {
      plymouth.enable = true;

      kernelParams = [
        "splash"
        "loglevel=3"
        "systemd.show_status=false"
        "vt.global_cursor_default=0"
      ];
    };

    systemd.services.plymouth-quit.serviceConfig = {
      # Clear VT1 text buffer while Plymouth still holds DRM master (so the
      # clear itself is invisible). When Plymouth then quits and releases
      # DRM, the kernel shows VT1 which is now blank rather than showing
      # old boot messages.
      ExecStartPre = "-${pkgs.bash}/bin/bash -c 'echo -ne \"\\033[2J\\033[H\" > /dev/tty1'";

      # Retain the splash image on the framebuffer when quitting.
      ExecStart = [
        ""
        "-${plymouth} quit --retain-splash"
      ];
    };
  };
}
