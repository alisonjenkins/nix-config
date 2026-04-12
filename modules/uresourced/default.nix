{ config, lib, pkgs, ... }:
let
  cfg = config.modules.uresourced;
  pkg = pkgs.uresourced;
in
{
  options.modules.uresourced = {
    enable = lib.mkEnableOption "uresourced, a user resource assignment daemon for graphical sessions";
  };

  config = lib.mkIf cfg.enable {
    # Install the system service, user service, and all drop-ins from the package
    systemd.packages = [ pkg ];

    # Enable the system service (Type=dbus, activated by user@.service)
    systemd.services.uresourced = {
      wantedBy = [ "multi-user.target" ];
    };

    # Enable the user service (started by graphical-session.target)
    systemd.user.services.uresourced = {
      wantedBy = [ "graphical-session.target" ];
    };

    # Add cgroup delegation for user sessions so uresourced can manage resources
    systemd.services."user@".serviceConfig.Delegate = "cpu io memory";

    # Install the D-Bus policy so the daemon can own its bus name
    services.dbus.packages = [ pkg ];

    # Install the default config
    environment.etc."uresourced.conf".source = "${pkg}/etc/uresourced.conf";
  };
}
