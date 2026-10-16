{ config, lib, pkgs, ... }:
let
  cfg = config.modules.rustBuildCache;
  tomlFormat = pkgs.formats.toml { };
in {
  options.modules.rustBuildCache = {
    enable = lib.mkEnableOption "sccache, slimmer dev profiles and periodic cargo-sweep of target dirs";

    sccacheSize = lib.mkOption {
      type = lib.types.str;
      default = "20G";
      description = "Hard cap on the sccache local disk cache (SCCACHE_CACHE_SIZE).";
    };

    sweep = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run cargo-sweep on a systemd user timer.";
      };

      roots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "${config.home.homeDirectory}/git" ];
        description = "Directories searched recursively for cargo target dirs.";
      };

      maxAgeDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 14;
        description = "Delete target artifacts not used for this many days.";
      };

      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar expression for the sweep.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.sccache pkgs.cargo-sweep ];

    # `[env]` reaches the compiler through cargo, so agents and IDEs that
    # never source a login shell still get the cache cap.
    home.file.".cargo/config.toml".source = tomlFormat.generate "cargo-config.toml" {
      build = {
        rustc-wrapper = lib.getExe pkgs.sccache;
        incremental = false;
      };
      env.SCCACHE_CACHE_SIZE = cfg.sccacheSize;
      profile.dev = {
        debug = "line-tables-only";
        split-debuginfo = "unpacked";
      };
    };

    systemd.user.services.cargo-sweep = lib.mkIf (cfg.sweep.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Delete stale cargo build artifacts";
      Service = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe pkgs.cargo-sweep)
          "sweep"
          "--recursive"
          "--hidden"
          "--time"
          (toString cfg.sweep.maxAgeDays)
        ] ++ cfg.sweep.roots);
      };
    };

    systemd.user.timers.cargo-sweep = lib.mkIf (cfg.sweep.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Delete stale cargo build artifacts";
      Timer = {
        OnCalendar = cfg.sweep.frequency;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
