{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.programs.copilot-cli;

  configDir = "${config.home.homeDirectory}/.copilot";

  scripts = import ./scripts.nix { inherit pkgs; };

  jsonMerge = { path, patch }:
    "run ${scripts.jsonMerge} ${lib.escapeShellArg path} ${pkgs.writeText "copilot-cli-patch.json" (builtins.toJSON patch)}";
in
{
  options.programs.copilot-cli = {
    enable = lib.mkEnableOption "declarative config management for the GitHub Copilot CLI (~/.copilot)" // { default = true; };

    trustedProjects = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra directories the CLI may read/write/exec without prompting.";
          };
          commandPatterns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Command patterns (as accepted by the CLI's own "don't ask again
              for `<cmd>` in this repo" prompt, e.g. `"gh pr:*"`) to
              pre-approve without prompting.
            '';
          };
        };
      });
      default = { };
      description = ''
        Per-project trust grants, keyed by the absolute project path as it
        appears under `permissions-config.json`'s `locations`. Merged
        additively with whatever the CLI has already granted interactively.
      '';
      example = lib.literalExpression ''
        {
          "/home/ali/git/nix-config".directories = [ "/home/ali/.agents/skills" ];
          "/home/ali/git/nix-config".commandPatterns = [ "gh pr:*" ];
        }
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Deep-merged into ~/.copilot/settings.json.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Deep-merged into ~/.copilot/mcp-config.json's `mcpServers` key.";
    };

    autoTrustSubdirsOf = lib.mkOption {
      type = lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.str;
            default = "${config.home.homeDirectory}/.config/copilot-cli/trusted-parents";
            description = ''
              Optional plain-text, newline-separated list of extra parent
              directories, read at activation time (never at Nix eval time,
              and never written into the store). Absent file is a no-op.
              Use it for parents that `discoverUnder` would not find.
            '';
          };

          discoverUnder = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "${config.home.homeDirectory}/git";
            description = ''
              Root scanned at activation time for grouping directories: an
              immediate subdirectory that is not itself a git repo but
              contains at least one (e.g. `~/git/<org>`). Each one found is
              treated as a parent. Discovery happens on the machine, so
              employer- or org-specific paths never appear in the flake
              source. `null` disables discovery.
            '';
          };

          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Directories to grant read/write/exec access to, for every git repo directly under a parent.";
          };

          commandPatterns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Command patterns to pre-approve, for every git repo directly under a parent.";
          };
        };
      };
      default = { };
      description = "Auto-discover projects under runtime-discovered parent directories and trust them.";
    };
  };

  config = lib.mkIf cfg.enable {
    # token-savior gives the CLI symbol-level code navigation; the bash wrapper
    # is needed because the config has no shell, so $PWD would not expand.
    programs.copilot-cli.mcpServers.token-savior = {
      command = "bash";
      args = [
        "-c"
        ''
          exec env WORKSPACE_ROOTS="$PWD" TOKEN_SAVIOR_CLIENT=copilot-cli TOKEN_SAVIOR_PROFILE=optimized ${pkgs.token-savior}/bin/token-savior
        ''
      ];
    };

    home.activation.copilotCliConfig = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatStringsSep "\n" (
        (lib.mapAttrsToList
          (proj: grant:
            "run ${scripts.trustProject} ${lib.escapeShellArg "${configDir}/permissions-config.json"} ${lib.escapeShellArg proj} "
            + lib.escapeShellArgs (grant.directories ++ [ "--" ] ++ grant.commandPatterns))
          cfg.trustedProjects)
        ++ lib.optional (cfg.settings != { }) (jsonMerge {
          path = "${configDir}/settings.json";
          patch = cfg.settings;
        })
        ++ lib.optional (cfg.mcpServers != { }) (jsonMerge {
          path = "${configDir}/mcp-config.json";
          patch = { mcpServers = cfg.mcpServers; };
        })
        ++ lib.optional (cfg.autoTrustSubdirsOf.directories != [ ] || cfg.autoTrustSubdirsOf.commandPatterns != [ ]) (
          "run ${scripts.trustParents} ${lib.escapeShellArg "${configDir}/permissions-config.json"} ${lib.escapeShellArg cfg.autoTrustSubdirsOf.file} ${lib.escapeShellArg (toString cfg.autoTrustSubdirsOf.discoverUnder)} "
          + lib.escapeShellArgs (cfg.autoTrustSubdirsOf.directories ++ [ "--" ] ++ cfg.autoTrustSubdirsOf.commandPatterns)
        )
      )
    );
  };
}
