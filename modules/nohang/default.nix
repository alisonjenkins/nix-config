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

  # Append protection rules to the base config
  configFile = pkgs.runCommand "nohang.conf" { } ''
    cat ${baseConfigFile} > $out
    cat >> $out <<'EXTRA'

## Protected processes added by NixOS module
${protectionLines}
EXTRA
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
