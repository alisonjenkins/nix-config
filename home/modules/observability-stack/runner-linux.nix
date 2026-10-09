# systemd user units: the pod, and the disk guard on a timer.
{ scripts, ... }:
let
  # NixOS puts the setuid newuidmap/newgidmap rootless podman needs in /run/wrappers.
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
in
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
