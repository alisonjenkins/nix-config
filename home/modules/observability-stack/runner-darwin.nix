# launchd user agents: the pod (which also creates and starts the stack's own podman machine), and the
# disk guard on an interval.
{ cfg, stateDir, relativeStateDir, scripts, ... }:
let
  env.PATH = "${cfg.podmanPackage}/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin";
  log = "${stateDir}/stack.log";
in
{
  # launchd opens the log file before the script runs, so the directory must exist.
  home.file."${relativeStateDir}/.keep".text = "";

  launchd.agents.observability-stack = {
    enable = true;
    config = {
      ProgramArguments = [ "${scripts.run}/bin/observability-stack-run" ];
      EnvironmentVariables = env;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };

  launchd.agents.observability-stack-guard = {
    enable = true;
    config = {
      ProgramArguments = [ "${scripts.guard}/bin/observability-stack-guard" ];
      EnvironmentVariables = env;
      StartInterval = 300;
      ProcessType = "Background";
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
