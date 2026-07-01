{ config, lib, pkgs, ... }:
let
  cfg = config.modules.nohang;
  pkg = pkgs.master.nohang;

  baseConfigFile =
    if cfg.enableDesktopNotifications
    then "${pkg}/etc/nohang/nohang-desktop.conf"
    else "${pkg}/etc/nohang/nohang.conf";

  allProtectedProcesses = cfg.protectedProcesses ++ cfg.extraProtectedProcesses;

  # Generate badness adjustment lines for protected processes
  protectionLines = lib.concatMapStringsSep "\n" (name:
    "@BADNESS_ADJ_RE_NAME -500 /// ^${name}$"
  ) allProtectedProcesses;

  # sed line-replacements for scalar key overrides. Each active nohang
  # threshold key appears exactly once in the preset as `key = value`;
  # the `^` anchor skips the "    Key: <name>" doc-comment lines.
  overrideCmds = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v:
    "sed -i -E 's|^${k}[[:space:]]*=.*|${k} = ${v}|' $out"
  ) cfg.settingsOverride);

  # Append protection rules to the base config, then apply key overrides.
  configFile = pkgs.runCommand "nohang.conf" { } ''
    cat ${baseConfigFile} > $out
    cat >> $out <<'EXTRA'

## Protected processes added by NixOS module
${protectionLines}
EXTRA
    ${overrideCmds}
  '';
in
{
  options.modules.nohang = {
    enable = lib.mkEnableOption "nohang, a sophisticated low memory handler";

    enableDesktopNotifications = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable desktop notifications via libnotify.
        Uses the nohang-desktop config preset which enables PSI monitoring,
        post-action GUI notifications, and low memory warnings.
      '';
    };

    protectedProcesses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Remote access
        "sshd"
        "amazon-ssm-agent"
        # VPN / overlay networking
        "tailscaled"
        # Core system daemons
        "systemd-journald"
        "systemd-resolved"
        "systemd-networkd"
        "NetworkManager"
        "dbus-broker"
        "dbus-daemon"
      ];
      description = ''
        Base process names to protect from being killed by nohang.
        Each name is matched as a regex against the process name
        with a badness adjustment of -500. The desktop config preset
        already protects display managers/compositors at -200.
        Use extraProtectedProcesses to add role-specific processes
        without overriding these defaults.
      '';
    };

    extraProtectedProcesses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Additional process names to protect, appended to protectedProcesses.
        Use this for role-specific processes (e.g. k3s, libvirtd, smbd).
      '';
    };

    settingsOverride = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        psi_excess_duration = "60";
        soft_threshold_max_psi = "60";
      };
      description = ''
        Override scalar keys in the nohang base preset. Each key = value
        pair replaces the matching `key = ...` line via sed. The key must
        already exist in the preset (all standard nohang thresholds do).

        Use to relax PSI/threshold values on hosts that generate legitimate
        transient memory pressure (e.g. heavy parallel compiles), which the
        desktop preset's PSI defaults (soft_threshold_max_psi = 40 on
        full_avg10, psi_excess_duration = 30) otherwise mistake for OOM.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nohang = {
      description = "Sophisticated low memory handler";
      documentation = [
        "man:nohang(8)"
        "https://github.com/hakavlad/nohang"
      ];
      after = [ "sysinit.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkg} --monitor --config ${configFile}";
        Slice = "hostcritical.slice";
        SyslogIdentifier = if cfg.enableDesktopNotifications then "nohang-desktop" else "nohang";
        KillMode = "mixed";
        Restart = "always";
        RestartSec = 0;

        CPUSchedulingResetOnFork = true;
        RestrictRealtime = "yes";

        TasksMax = 25;
        MemoryMax = "100M";
        MemorySwapMax = "100M";

        UMask = 27;
        ProtectSystem = "strict";
        ReadWritePaths = "/var/log";
        InaccessiblePaths = "/home /root";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        MemoryDenyWriteExecute = "yes";
        RestrictNamespaces = "yes";
        LockPersonality = "yes";
        PrivateTmp = true;
        DeviceAllow = "/dev/kmsg rw";
        DevicePolicy = "closed";

        CapabilityBoundingSet = [
          "CAP_KILL"
          "CAP_IPC_LOCK"
          "CAP_SYS_PTRACE"
          "CAP_DAC_READ_SEARCH"
          "CAP_DAC_OVERRIDE"
          "CAP_AUDIT_WRITE"
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_SYS_RESOURCE"
          "CAP_SYSLOG"
        ];
      } // lib.optionalAttrs cfg.enableDesktopNotifications {
        # nohang uses notify-send for desktop notifications
        Environment = "PATH=${lib.makeBinPath [ pkgs.libnotify ]}:$PATH";
      };
    };
  };
}
