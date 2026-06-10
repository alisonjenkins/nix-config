{ config, lib, pkgs, ... }:
let
  cfg = config.modules.githubActionsRunner;
  scripts = import ./scripts.nix { inherit pkgs lib cfg; };
in
{
  imports = [ ./common.nix ];

  config = lib.mkIf cfg.enable {
    # Pre-stage the writable RUNNER_ROOT. No copy of the store package needed:
    # the wrapped config.sh/run.sh write mutable state here while reading the
    # immutable runner assets from the nix store via RUNNER_ROOT.
    #
    # NB: nix-darwin only runs the preActivation/extraActivation/postActivation
    # phases of system.activationScripts — arbitrary keys are NOT executed. So
    # this must live in postActivation (runs as root during `darwin-rebuild
    # switch`), not a custom-named script.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p ${lib.escapeShellArg (toString cfg.runnerDir)}
      chown ${cfg.user}:staff ${lib.escapeShellArg (toString cfg.runnerDir)}
      chmod 0750 ${lib.escapeShellArg (toString cfg.runnerDir)}
    '';

    launchd.daemons.github-actions-runner-poller.serviceConfig = {
      Label = "org.nixos.github-actions-runner-poller";
      ProgramArguments = [ (lib.getExe scripts.pollScript) ];
      StartInterval = cfg.pollInterval;
      RunAtLoad = true;
      KeepAlive = false;
      # Poller (and thus jobs) run as the target user, not root.
      UserName = cfg.user;
      # Log under runnerDir (owned by cfg.user) — the daemon runs as cfg.user
      # and cannot create files in /var/log (root:wheel).
      StandardOutPath = "${toString cfg.runnerDir}/poller.log";
      StandardErrorPath = "${toString cfg.runnerDir}/poller.log";
      EnvironmentVariables = {
        HOME = toString cfg.runnerDir;
        RUNNER_ROOT = toString cfg.runnerDir;
        # Minimal PATH so the poller's own tooling resolves; spawnScript injects
        # the richer job PATH (nix, git, ...) itself.
        PATH = "${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.git pkgs.nix ]}:/usr/bin:/bin";
      };
    };
  };
}
