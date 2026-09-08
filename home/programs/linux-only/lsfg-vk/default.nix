{ config, lib, pkgs, ... }:

let
  cfg = config.programs.lsfg-vk;

  patchConfig = pkgs.writers.writePython3Bin "lsfg-vk-patch-config"
    {
      libraries = [ pkgs.python3Packages.tomli-w ];
      flakeIgnore = [ "E501" ];
    }
    (builtins.readFile ./patch_config.py);

  dropNulls = lib.filterAttrs (_: v: v != null);

  managed = pkgs.writeText "lsfg-vk-managed.json" (builtins.toJSON {
    global = dropNulls cfg.global;
    profiles = lib.mapAttrsToList (_: dropNulls) cfg.profiles;
  });

  # Keys and defaults follow lsfg-vk 2.0.0's config parser, which rejects
  # unknown keys; anything not listed here cannot be written.
  profileModule = { name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = ''
          Profile name shown in lsfg-vk-ui, also selectable with
          LSFGVK_PROFILE. Doubles as the merge key: an existing profile with
          this name is replaced, any other profile is left alone.
        '';
      };

      active_in = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "helldivers2.exe" ];
        description = ''
          Linux binary names, Windows executables, process names, or path
          suffixes that activate this profile.
        '';
      };

      multiplier = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Frames presented per frame rendered. Hot-reloads.";
      };

      flow_scale = lib.mkOption {
        type = lib.types.numbers.between 0.25 1.0;
        default = 1.0;
        description = "Resolution scale for motion estimation. Hot-reloads.";
      };

      performance_mode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use the lighter frame generation model. Hot-reloads.";
      };

      pacing = lib.mkOption {
        type = lib.types.enum [ "vsync" ];
        default = "vsync";
        description = ''
          Frame pacing mode. `vsync` presents generated frames as soon as
          they are ready and relies on V-Sync to avoid skipped frames; it is
          the only mode lsfg-vk 2.0.0 implements.
        '';
      };

      override_present_mode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Force the swapchain to FIFO (V-Sync) for the pacing mode.";
      };

      preserve_swapchain_image_count = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Leave the application's swapchain image count unchanged.";
      };
    };
  };
in
{
  options.programs.lsfg-vk = {
    enable = lib.mkEnableOption "declared lsfg-vk profiles patched into the live config";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.lsfg-vk-ui;
      defaultText = lib.literalExpression "pkgs.lsfg-vk-ui";
      description = "lsfg-vk build whose CLI validates the patched file.";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/lsfg-vk/conf.toml";
      description = "The lsfg-vk config file to patch.";
    };

    global = {
      dll = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path to Lossless.dll when it is outside the searched locations.
          Null keeps whatever the file already has.
        '';
      };

      allow_fp16 = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Allow half-precision shaders. Large speed-up on AMD, no effect on
          recent NVIDIA, slower on GTX 10-series and older. Null keeps
          whatever the file already has (lsfg-vk defaults to true).
        '';
      };

      log_level = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "debug" "info" "warning" "error" ]);
        default = null;
        description = "Layer log level. Null keeps whatever the file already has.";
      };

      log_file = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Write layer logs to this file. Null keeps whatever the file already has.";
      };
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule profileModule);
      default = { };
      description = ''
        Profiles to keep in the config. Merged into the existing file at
        activation, matched by name, so profiles created in lsfg-vk-ui
        survive and the file stays writable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Validation is a warning, not a failure: the file is shared with
    # lsfg-vk-ui and a stale hand-written key must not block activation.
    home.activation.patchLsfgVkConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe patchConfig} ${managed} ${lib.escapeShellArg cfg.configFile}
      run ${cfg.package}/bin/lsfg-vk-cli validate -c ${lib.escapeShellArg cfg.configFile} >/dev/null \
        || warnEcho "lsfg-vk: ${cfg.configFile} is rejected by lsfg-vk-cli validate; run it by hand for the reason"
    '';
  };
}
