{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.wifiRegdomFromTimezone;

  script = pkgs.writeShellApplication {
    name = "wifi-regdom-from-timezone";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.iw ];
    text = ''
      state="''${RUNTIME_DIRECTORY:-/run/wifi-regdom-from-timezone}/timezone"
      tz="$(readlink -f /etc/localtime)"
      tz="''${tz#*/zoneinfo/}"
      if [[ -f "$state" && "$(<"$state")" == "$tz" ]]; then
        exit 0
      fi
      country="$(awk -v tz="$tz" '$3 == tz { print $1; exit }' ${pkgs.tzdata}/share/zoneinfo/zone.tab)"
      if [[ -z "$country" ]]; then
        printf 'event=regdom_skip reason=no_country timezone=%q\n' "$tz" >&2
      else
        iw reg set "$country"
        printf 'event=regdom_set country=%s timezone=%q\n' "$country" "$tz" >&2
      fi
      printf '%s' "$tz" > "$state"
    '';
  };
in {
  options.modules.wifiRegdomFromTimezone.enable = mkEnableOption ''
    setting the wifi regulatory domain from the system timezone.

    The kernel otherwise learns the country from access point beacons
    (802.11d); on the world regdomain (`00`) 5 GHz channels are restricted
    and 6 GHz is blocked. This pins the country from the timezone instead.
    Pair it with services.automatic-timezoned so the country follows the
    machine. The country is applied when the timezone changes, and
    NetworkManager or wpa_supplicant may still override it later from an
    access point's 802.11d beacon
  '';

  config = mkIf cfg.enable {
    systemd = {
      services.wifi-regdom-from-timezone = {
        description = "Set the wifi regulatory domain from the timezone";
        after = [ "automatic-timezoned.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe script;
          # Remembers the last timezone handled, so each timer run is a no-op
          # until it changes and does not keep overriding 802.11d.
          RuntimeDirectory = "wifi-regdom-from-timezone";
          RuntimeDirectoryPreserve = "yes";
        };
      };
      # Not a path unit: systemd watches /etc/localtime's current target, so
      # replacing the symlink a second time goes unnoticed.
      timers.wifi-regdom-from-timezone = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "0";
          OnUnitActiveSec = "30s";
        };
      };
    };
  };
}
