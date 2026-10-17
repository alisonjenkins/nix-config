{ config, lib, pkgs, ... }:
let
  cfg = config.modules.rustBuildCache;
  tomlFormat = pkgs.formats.toml { };

  pruneExternalTargets = pkgs.writeShellApplication {
    name = "prune-external-cargo-targets";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
    text = ''
      max_age_days=$1
      shift
      shopt -s nullglob

      for pattern in "$@"; do
        # the glob is the point: it must expand here
        # shellcheck disable=SC2231
        for dir in $pattern; do
          [[ -d $dir && ! -L $dir && -f $dir/CACHEDIR.TAG ]] || continue
          if [[ -n $(find "$dir" -type f -mtime "-$max_age_days" -print -quit) ]]; then
            continue
          fi
          printf 'event=prune_target path=%q\n' "$dir" >&2
          rm -rf -- "$dir"
        done
      done
    '';
  };

  sweepSchedule = {
    OnCalendar = cfg.sweep.frequency;
    Persistent = true;
    RandomizedDelaySec = "30m";
  };
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
        default = 1;
        description = "Delete target artifacts not used for this many days.";
      };

      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar expression for the sweep.";
      };

      externalTargetGlobs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "${config.home.homeDirectory}/.cache/*/target"
          "${config.home.homeDirectory}/git/.cm-shared-target*"
          "${config.home.homeDirectory}/git/*/.cm-shared-target*"
        ];
        description = ''
          Globs of CARGO_TARGET_DIR directories that live outside any project,
          which cargo-sweep cannot find. A match is deleted whole when no file
          in it changed within maxAgeDays. Only directories holding the
          CACHEDIR.TAG that cargo writes are touched.
        '';
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
      Timer = sweepSchedule;
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.cargo-prune-external-targets = lib.mkIf (cfg.sweep.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Delete stale cargo target dirs outside any project";
      Service = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe pruneExternalTargets)
          (toString cfg.sweep.maxAgeDays)
        ] ++ cfg.sweep.externalTargetGlobs);
      };
    };

    systemd.user.timers.cargo-prune-external-targets = lib.mkIf (cfg.sweep.enable && pkgs.stdenv.isLinux) {
      Unit.Description = "Delete stale cargo target dirs outside any project";
      Timer = sweepSchedule;
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
