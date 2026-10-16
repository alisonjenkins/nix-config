# systemd user units: the pod, the disk guard on a timer, and the weekly review on a timer.
{ lib, cfg, scripts, ... }:
let
  # NixOS puts the setuid newuidmap/newgidmap rootless podman needs in /run/wrappers.
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
  # The review starts `claude`, which lives in the user's profile or ~/.local/bin.
  reviewPath = "${path}:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:%h/.local/bin";
in
lib.mkMerge [
  {
    systemd.user.services.observability-stack = {
      Unit.Description = "Local observability stack (Loki, Tempo, Prometheus, Grafana, collector)";
      Service = {
        ExecStart = "${scripts.run}/bin/observability-stack-run";
        Environment = [ path ];
        Restart = "always";
        RestartSec = 15;
        TimeoutStopSec = 60;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.observability-stack-guard = {
      Unit.Description = "Report when the observability data directories pass the disk budget";
      Service = {
        Type = "oneshot";
        ExecStart = "${scripts.guard}/bin/observability-stack-guard";
        Environment = [ path ];
      };
    };

    systemd.user.timers.observability-stack-guard = {
      Unit.Description = "Check observability disk use every five minutes";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  }

  (lib.mkIf cfg.review.enable {
    systemd.user.services.observability-stack-review = {
      Unit = {
        Description = "Weekly two-tier token review (findings go to ${cfg.review.stateDir})";
        Wants = [ "observability-stack.service" ];
        After = [ "observability-stack.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${scripts.review}/bin/observability-stack-review";
        Environment = [ reviewPath ];
        TimeoutStartSec = "2h";
        Nice = 10;
      };
    };

    systemd.user.timers.observability-stack-review = {
      Unit.Description = "Run the weekly token review";
      Timer = {
        OnCalendar = cfg.review.schedule;
        # A review missed while the machine was off runs at the next start.
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  })
]
