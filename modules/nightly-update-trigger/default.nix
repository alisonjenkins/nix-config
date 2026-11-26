# Starts the nightly flake update (.github/workflows/update.yaml) from a
# systemd timer at home, instead of GitHub's cron.
#
# Why: the home self-hosted runners do the nightly's work, and power is cheap
# 00:30-05:30 UK time. GitHub's scheduled runs started the 02:00 job 7-10
# hours late (2026-11-21..25), so the work ran on daytime power. A timer here
# fires on time in local time (Europe/London, so BST is handled) and has
# Persistent=false: a night the host was down is skipped, not run late in the
# day. update-shepherd.yaml opens an issue when a night is missed.
#
# Token: a fine-grained GitHub token, repository alisonjenkins/nix-config
# only, permission "Actions: read and write" and nothing else (it can start
# and cancel workflow runs; it cannot read or push code or touch secrets).
# Store it with sops under the key given by `tokenSecret`. The dispatch
# script and its tests are .github/scripts/nightly-dispatch.sh and
# .github/scripts/tests/nightly-dispatch.bats.
#
# Check it with:  systemctl list-timers nightly-update-trigger
#                 journalctl -u nightly-update-trigger
# Run it by hand: systemctl start nightly-update-trigger
{ config, inputs, lib, pkgs, ... }:
let
  cfg = config.modules.nightlyUpdateTrigger;
  dispatch = pkgs.writeShellApplication {
    name = "nightly-dispatch";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = builtins.readFile (inputs.self + "/.github/scripts/nightly-dispatch.sh");
  };
in
{
  options.modules.nightlyUpdateTrigger = {
    enable = lib.mkEnableOption "a local timer that starts the nightly flake update workflow";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 02:00:00";
      description = ''
        When to start the workflow, in the host's local time (systemd.time(7)).
        Keep it inside the 00:30-05:30 UK cheap-power window, with room for
        the run to finish.
      '';
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "alisonjenkins/nix-config";
      description = "Repository (owner/name) whose workflow is started.";
    };

    workflow = lib.mkOption {
      type = lib.types.str;
      default = "update.yaml";
      description = "Workflow file to start. It must have a workflow_dispatch trigger.";
    };

    ref = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch the workflow runs on.";
    };

    tokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "nightly-dispatch-token";
      description = "Name of the sops secret holding the token (see the header of this module).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.tokenSecret} = {
      owner = "root";
      mode = "0400";
    };

    systemd.services.nightly-update-trigger = {
      description = "Start the nightly flake update workflow on GitHub";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        REPO = cfg.repo;
        WORKFLOW = cfg.workflow;
        REF = cfg.ref;
        TOKEN_FILE = "%d/token";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe dispatch;
        LoadCredential = "token:${config.sops.secrets.${cfg.tokenSecret}.path}";
        DynamicUser = true;
        # It only talks to api.github.com.
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        # AF_UNIX: glibc resolves names through nscd.
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    systemd.timers.nightly-update-trigger = {
      description = "Start the nightly flake update inside the cheap-power window";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # A missed night is skipped rather than run on daytime power.
        Persistent = false;
        AccuracySec = "1min";
      };
    };
  };
}
