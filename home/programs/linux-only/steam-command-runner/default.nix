{ lib, config, pkgs, ... }:

let
  cfg = config.programs.steamCommandRunner;

  tomlConfig =
    lib.optionalAttrs (cfg.preCommand != "") { pre_command = cfg.preCommand; }
    // lib.optionalAttrs (cfg.defaultProton != null) { default_proton = cfg.defaultProton; }
    // {
      default_mode = cfg.defaultMode;
      shim_debug = cfg.shimDebug;
      env = cfg.env;
      inner_env = cfg.innerEnv;
      gamescope = { skip_pre_command = cfg.gamescopeSkipPreCommand; }
        // lib.optionalAttrs (cfg.gamescopeArgs != "") { args = cfg.gamescopeArgs; };
    };
in
{
  options.programs.steamCommandRunner = {
    enable = lib.mkEnableOption "steam-command-runner global configuration";

    preCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "obs-gamecapture gamemoderun";
      description = ''
        Command to prepend to every game launch, except one going through
        gamescope while `gamescopeSkipPreCommand` is true (the default) —
        set that to false if this should apply there too. Wrappers chain
        left to right — each execs the next, so the leftmost is outermost.
        LD_PRELOAD and similar env vars set by an outer wrapper survive an
        inner wrapper's own exec, so order between env-setting shims rarely
        matters, but keep the one whose exit code or output Steam should see
        last.
      '';
    };

    defaultProton = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default Proton version (name as shown in Steam, or path).";
    };

    defaultMode = lib.mkOption {
      type = lib.types.enum [ "native" "proton" "auto" ];
      default = "auto";
      description = "Default execution mode for games.";
    };

    shimDebug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable verbose shim/runner logging to ~/.steam-command-runner*.log.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables applied to the process the runner execs. When
        gamescope is in play that process is gamescope, so gamescope
        inherits these too — do not put MANGOHUD or similar implicit-layer
        vars here, use `innerEnv`.
      '';
    };

    innerEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables applied to the game process only, past
        gamescope's `--`. Use for MANGOHUD, MANGOHUD_CONFIG, ENABLE_VKBASALT
        and other implicit Vulkan layer vars that would otherwise load into
        gamescope's own Vulkan instance and segfault it at exit.
      '';
    };

    gamescopeArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "-w 2540 -h 1440 -W 2540 -H 1440 -b --rt -F fsr -r 120";
      description = "Arguments passed to gamescope when the shim wraps a launch.";
    };

    gamescopeSkipPreCommand = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Skip `preCommand` when launching under Gamescope.";
    };

    games = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        freeformType = (pkgs.formats.toml { }).type;
      });
      default = { };
      example = {
        "553850" = {
          hooks.pre_launch.command = "uhk-switch-keymap HD2";
          hooks.post_exit.command = "uhk-switch-keymap QWR";
        };
      };
      description = ''
        Per-game overrides, keyed by Steam AppID. Each attrset is written
        verbatim as TOML to
        `~/.config/steam-command-runner/games/<appid>.toml` — field names
        match `GameConfig` in the runner's own source
        (`src/config/game.rs`: `hooks.pre_launch`/`hooks.post_exit`,
        `mode`, `proton`, `env`, `launch_args`, ...), not this module's own
        camelCase option names.
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    invalidAppIds = lib.filter (appId: builtins.match "[0-9]+" appId == null) (lib.attrNames cfg.games);
  in {
    assertions = [
      {
        assertion = invalidAppIds == [ ];
        message =
          "programs.steamCommandRunner.games is keyed by Steam AppID (digits only) — "
          + "got: ${toString invalidAppIds}";
      }
    ];

    xdg.configFile =
      { "steam-command-runner/config.toml".source =
        (pkgs.formats.toml { }).generate "steam-command-runner-config.toml" tomlConfig;
      }
      // lib.mapAttrs' (appId: gameConfig: lib.nameValuePair
        "steam-command-runner/games/${appId}.toml"
        { source = (pkgs.formats.toml { }).generate "steam-command-runner-game-${appId}.toml" gameConfig; }
      ) cfg.games;
  });
}
