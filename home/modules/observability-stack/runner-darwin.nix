# launchd user agents: the pod (which also creates and starts the stack's own podman machine), the
# disk guard on an interval, and the weekly review on a calendar interval.
{ lib, cfg, stateDir, relativeStateDir, homeDirectory, scripts, ... }:
let
  env.PATH = "${cfg.podmanPackage}/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin";
  reviewEnv.PATH = "${homeDirectory}/.local/bin:${homeDirectory}/.nix-profile/bin:${env.PATH}";
  log = "${stateDir}/stack.log";

  weekdays = { Sun = 0; Mon = 1; Tue = 2; Wed = 3; Thu = 4; Fri = 5; Sat = 6; };
  # review.schedule is "<Day> HH:MM"; launchd has no OnCalendar. A value this does not
  # match fails an assertion in default.nix.
  parsed = builtins.match "(Sun|Mon|Tue|Wed|Thu|Fri|Sat) ([01][0-9]|2[0-3]):([0-5][0-9])" cfg.review.schedule;
  number = s: lib.toInt (lib.removePrefix "0" s);
  interval = {
    Weekday = weekdays.${builtins.elemAt parsed 0};
    Hour = number (builtins.elemAt parsed 1);
    Minute = number (builtins.elemAt parsed 2);
  };
in
lib.mkMerge [
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

  (lib.mkIf (cfg.review.enable && parsed != null) {
    launchd.agents.observability-stack-review = {
      enable = true;
      config = {
        ProgramArguments = [ "${scripts.review}/bin/observability-stack-review" ];
        EnvironmentVariables = reviewEnv;
        StartCalendarInterval = [ interval ];
        ProcessType = "Background";
        StandardOutPath = log;
        StandardErrorPath = log;
      };
    };
  })
]
