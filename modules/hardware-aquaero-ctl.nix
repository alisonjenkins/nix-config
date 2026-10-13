{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hardware.aquaeroCtl;

  # What v1 can drive: the radiator fans (fan 4) from the coolant sensor
  # (Sensor 1). The device holds exactly 16 curve points.
  supportedFan = "4";
  supportedSensor = 1;
  maxPoints = 16;

  desired = {
    device_serial = cfg.serial;
    inherit (cfg) mode;
    fans =
      mapAttrs (_: fan: {
        inherit (fan) sensor;
        min_percent = fan.minPercent;
        points = map (point: {inherit (point) temp percent;}) fan.points;
      })
      cfg.fans;
  };
  desiredFile = pkgs.writeText "aquaero-ctl-desired.json" (builtins.toJSON desired);

  # One list of problems per fan; each names the value that caused it
  # (the checks mirror the tool's own, so a bad value fails the build instead
  # of failing a switch at 3 a.m.).
  problemsFor = n: fan: let
    where = "hardware.aquaeroCtl.fans.${n}";
    temps = map (point: point.temp) fan.points;
    percents = map (point: point.percent) fan.points;
    pairs = list: zipLists (take (length list - 1) list) (drop 1 list);
  in
    optional (n != supportedFan) "${where}: fan ${n} is not supported; v1 drives fan ${supportedFan} only"
    ++ optional (fan.sensor != supportedSensor) "${where}.sensor: sensor ${toString fan.sensor} is not supported; v1 uses sensor ${toString supportedSensor} only"
    ++ optional (fan.minPercent < 0 || fan.minPercent > 100) "${where}.minPercent: ${toString fan.minPercent} is outside 0 to 100"
    ++ optional (length fan.points < 2) "${where}.points: a curve needs at least 2 points, got ${toString (length fan.points)}"
    ++ optional (length fan.points > maxPoints) "${where}.points: the device holds at most ${toString maxPoints} points, got ${toString (length fan.points)}"
    ++ concatMap (
      point:
        optional (point.temp < 0 || point.temp > 100) "${where}.points: temperature ${toString point.temp} is outside 0 to 100"
        ++ optional (point.percent > 100) "${where}.points: percent ${toString point.percent} is above 100"
        ++ optional (point.percent < fan.minPercent) "${where}.points: percent ${toString point.percent} at ${toString point.temp} °C is below minPercent ${toString fan.minPercent}"
    )
    fan.points
    ++ concatMap (
      pair:
        optional (pair.snd <= pair.fst) "${where}.points: temperature ${toString pair.snd} does not rise above the previous point's ${toString pair.fst}"
    ) (pairs temps)
    ++ concatMap (
      pair:
        optional (pair.snd < pair.fst) "${where}.points: percent ${toString pair.snd} is below the previous point's ${toString pair.fst}"
    ) (pairs percents);

  allProblems = concatLists (mapAttrsToList problemsFor cfg.fans);
in {
  options.hardware.aquaeroCtl = {
    enable = mkEnableOption "writing a fan curve to an Aquacomputer aquaero fan controller (stored on the device)";

    package = mkOption {
      type = types.package;
      default = pkgs.aquaero-ctl;
      defaultText = literalExpression "pkgs.aquaero-ctl";
      description = "The aquaero-ctl tool.";
    };

    mode = mkOption {
      type = types.enum ["apply" "check"];
      default = "apply";
      description = ''
        `apply` writes the curve when the device differs. `check` only reports
        drift in the journal and never writes.
      '';
    };

    serial = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "21998-56576";
      description = "Which device (the USB serial); null means the only aquaero present.";
    };

    backupDir = mkOption {
      type = types.path;
      default = "/var/lib/aquaero-ctl/backups";
      description = "Where the configuration saved before every write goes.";
    };

    loggedInUserAccess = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Also give the logged-in desktop user read/write access to this one
        device (its hidraw nodes and its USB node, for passing it to a VM),
        through logind's `uaccess`. Nothing else is opened up.
      '';
    };

    fans = mkOption {
      default = {};
      description = "Fan curves, by fan number. v1 supports fan 4 only.";
      type = types.attrsOf (types.submodule {
        options = {
          sensor = mkOption {
            type = types.int;
            description = "The temperature sensor that drives the fan (v1: sensor 1, the coolant).";
          };
          minPercent = mkOption {
            type = types.int;
            description = "The fan speed floor, 0 to 100 percent.";
          };
          points = mkOption {
            type = types.listOf (types.submodule {
              options = {
                temp = mkOption {
                  type = types.number;
                  description = "Degrees Celsius.";
                };
                percent = mkOption {
                  type = types.number;
                  description = "Fan speed at that temperature.";
                };
              };
            });
            description = "Curve points; temperatures strictly increasing, speeds never decreasing and not below minPercent.";
          };
        };
      });
    };
  };

  config = mkIf cfg.enable {
    assertions =
      [
        {
          assertion = cfg.fans != {};
          message = "hardware.aquaeroCtl.fans: configure at least one fan (v1 supports fan ${supportedFan})";
        }
      ]
      ++ map (message: {
        assertion = false;
        inherit message;
      })
      allProblems;

    environment.systemPackages = [cfg.package];

    users.users.aquaero-ctl = {
      isSystemUser = true;
      group = "aquaero-ctl";
      description = "aquaero fan curve writer";
    };
    users.groups.aquaero-ctl = {};

    systemd.tmpfiles.rules = ["d ${cfg.backupDir} 0750 aquaero-ctl aquaero-ctl - -"];

    systemd.services.aquaero-ctl-apply = {
      description = "Make the aquaero fan curve match the configuration";
      wantedBy = ["multi-user.target"];
      # Changing the desired state restarts the unit, so a switch applies it.
      restartTriggers = [desiredFile];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "aquaero-ctl";
        Group = "aquaero-ctl";
        RuntimeDirectory = "aquaero-ctl";
        ExecStart = escapeShellArgs ([
            "${cfg.package}/bin/aquaero-ctl"
            "apply"
            "--desired"
            "${desiredFile}"
            "--backup-dir"
            "${cfg.backupDir}"
            "--lock-file"
            "/run/aquaero-ctl/lock"
          ]
          ++ optional (cfg.mode == "check") "--check");

        # Only the one device node it needs, and nothing else.
        DevicePolicy = "closed";
        DeviceAllow = ["char-hidraw rw"];
        ReadWritePaths = [cfg.backupDir];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = "none";
        RestrictNamespaces = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    # A device that appears later (plugged in, or handed back by a VM) gets the
    # curve too. The oneshot stays "active" so a switch restarts it; this
    # restarts it on the device event instead.
    systemd.services.aquaero-ctl-reapply = {
      description = "Re-run the aquaero fan curve after the device appears";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl --no-block restart aquaero-ctl-apply.service";
      };
    };

    # As a rules package (70-), not extraRules (99-local): logind applies the
    # uaccess tag in 73-seat-late, so a rule that adds it must sort before that.
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/70-aquaero-ctl.rules" (
        ''
          # The service's user may open this device's hidraw nodes.
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0c70", ATTRS{idProduct}=="f001", GROUP="aquaero-ctl", MODE="0660"
          ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0c70", ATTRS{idProduct}=="f001", TAG+="systemd", ENV{SYSTEMD_WANTS}+="aquaero-ctl-reapply.service"
        ''
        + optionalString cfg.loggedInUserAccess ''
          # The logged-in user too (logind ACL), for dumps and for the Windows VM.
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0c70", ATTRS{idProduct}=="f001", TAG+="uaccess"
          SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0c70", ATTR{idProduct}=="f001", TAG+="uaccess"
        ''
      ))
    ];
  };
}
