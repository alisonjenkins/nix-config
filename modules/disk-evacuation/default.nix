{ config, lib, pkgs, ... }:
let
  cfg = config.modules.diskEvacuation;

  diskEvac = pkgs.writers.writePython3Bin "disk-evac"
    { flakeIgnore = [ "E501" ]; }
    (builtins.readFile ./disk_evac.py);

  poolGlob = "${cfg.poolRoot}/*";
  stateDir = "/var/lib/disk-evacuation";

  skipArgs = lib.concatMap (s: [ "--skip" s ]) cfg.skipBranches;
  priorityArgs = lib.concatMap (p: [ "--priority" p ]) cfg.priority;

  # Plans are made once per source and reused: a replan walks the failing
  # disk's directory tree again. Delete the plan file to replan.
  runScript = pkgs.writeShellApplication {
    name = "disk-evacuation-run";
    runtimeInputs = [ diskEvac pkgs.coreutils pkgs.gnugrep pkgs.util-linux ];
    text = ''
      for src in ${lib.escapeShellArgs cfg.sources}; do
        if ! findmnt -n -o OPTIONS --mountpoint "$src" | grep -Eq '(^|,)ro(,|$)'; then
          echo "event=refused reason=source_not_readonly source=$src" >&2
          exit 1
        fi
        name=$(basename "$src")
        plan="${stateDir}/$name.plan.json"
        if [[ ! -s "$plan" ]]; then
          disk-evac plan --source "$src" --pool-glob ${lib.escapeShellArg poolGlob} \
            ${lib.escapeShellArgs skipArgs} ${lib.escapeShellArgs priorityArgs} \
            --reserve-gib ${toString cfg.reserveGiB} --out "$plan"
        fi
        disk-evac run --plan "$plan" --pool-glob ${lib.escapeShellArg poolGlob} \
          ${lib.escapeShellArgs skipArgs} --state "${stateDir}/$name" \
          --budget-gib ${toString cfg.budgetGiB} \
          --reserve-gib ${toString cfg.reserveGiB} \
          --max-consecutive-errors ${toString cfg.maxConsecutiveErrors} \
          --rate-mib-s ${toString cfg.rateMiBPerSec}
      done
    '';
  };

  # Skip the run while the array is busy: never alongside a snapraid sync or
  # scrub (an `after` ordering would not stop that), and the same IO-pressure
  # gate the snapraid units use.
  deferCheck = pkgs.writeShellScript "disk-evacuation-defer-check" ''
    if ${config.systemd.package}/bin/systemctl is-active --quiet snapraid-sync.service snapraid-scrub.service; then
      exit 1
    fi
    A=$(${pkgs.gawk}/bin/awk '/^some/{for(i=1;i<=NF;i++) if($i ~ /^avg300=/){sub(/avg300=/,"",$i); print $i}}' /proc/pressure/io)
    ${pkgs.gawk}/bin/awk -v a="''${A:-0}" 'BEGIN{ exit !((a+0) < 40) }'
  '';
in
{
  options.modules.diskEvacuation = {
    enable = lib.mkEnableOption "copying files off failing disks onto healthy pool branches";

    sources = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      example = [ "/mnt/rescue/sdg" ];
      description = ''
        Mount points of the failing disks. Each must be mounted read-only;
        the service refuses to run otherwise, so it can never modify a source
        or treat the live pool as one.
      '';
    };

    poolRoot = lib.mkOption {
      type = lib.types.path;
      default = "/media/disks";
      description = "Directory whose children are the healthy pool branches (the mergerfs branch glob is <poolRoot>/*).";
    };

    skipBranches = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ "/media/disks/failing-disk-part1" ];
      description = "Pool branches that are never a destination, such as disks that are degrading but still in the pool.";
    };

    priority = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Relative-path prefixes copied first, in order, so irreplaceable data is read before re-obtainable media.";
    };

    reserveGiB = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 50;
      description = "Free space left on every destination branch after the copy.";
    };

    budgetGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Most data copied from each source per service run (the limit applies to each source separately); the next run resumes from the manifest.";
    };

    rateMiBPerSec = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 40;
      description = "Average read throttle on the failing disk, in MiB/s; 0 is unlimited.";
    };

    maxConsecutiveErrors = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Stop the run after this many failed files in a row.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.sources != [ ];
      message = "modules.diskEvacuation.sources must list at least one mount point.";
    }];

    environment.systemPackages = [ diskEvac ];

    # Started by hand or by an automation (systemctl start disk-evacuation);
    # there is deliberately no timer or wantedBy.
    systemd.services.disk-evacuation = {
      description = "Copy files off failing disks onto healthy pool branches";
      serviceConfig = {
        Type = "oneshot";
        ExecCondition = "${deferCheck}";
        ExecStart = "${runScript}/bin/disk-evacuation-run";
        StateDirectory = "disk-evacuation";
        IOSchedulingClass = "idle";
        Nice = 19;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ stateDir cfg.poolRoot ];
        ReadOnlyPaths = cfg.sources;
        CapabilityBoundingSet = [ "CAP_CHOWN" "CAP_FOWNER" "CAP_DAC_OVERRIDE" "CAP_DAC_READ_SEARCH" ];
      };
    };
  };
}
