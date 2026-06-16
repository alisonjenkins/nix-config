{ config, lib, pkgs, ... }:
let
  cfg = config.modules.githubActionsRunner;
  scripts = import ./scripts.nix { inherit pkgs lib cfg; };
in
{
  imports = [ ./common.nix ];

  config = lib.mkIf cfg.enable {
    # Dedicated unprivileged user the poller, runner and jobs run as. The
    # official runner refuses to run as root (RUNNER_ALLOW_RUNASROOT=0), and a
    # dedicated user keeps job state isolated.
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = toString cfg.runnerDir;
      createHome = false;
      description = "GitHub Actions runner";
    };
    users.groups.${cfg.user} = { };

    # Path-agnostic creation of the writable RUNNER_ROOT (vs systemd
    # StateDirectory, which only handles paths under /var/lib).
    systemd.tmpfiles.rules = [
      "d ${toString cfg.runnerDir} 0750 ${cfg.user} ${cfg.user} -"
    ];

    # The poller: a oneshot run every pollInterval via a timer. Logs go to the
    # journal (journalctl -u github-actions-runner-poller). True ~0MB idle —
    # nothing persists between ticks unless a job is actually queued.
    systemd.services.github-actions-runner-poller = {
      description = "On-demand GitHub Actions runner poller";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # Tools the poller itself needs; spawnScript injects the richer job PATH.
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
        pkgs.git
        pkgs.nix
        pkgs.gnugrep
        pkgs.procps
      ];
      environment = {
        HOME = toString cfg.runnerDir;
        RUNNER_ROOT = toString cfg.runnerDir;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = lib.getExe scripts.pollScript;
        # A spawned ephemeral runner outlives the oneshot via setsid-like
        # behaviour is not needed: run.sh is invoked synchronously inside the
        # poll (the oneshot stays active for the duration of the job).
        TimeoutStartSec = "infinity";
      };
    };

    systemd.timers.github-actions-runner-poller = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "${toString cfg.pollInterval}s";
        AccuracySec = "5s";
        Persistent = true;
      };
    };
  };
}
