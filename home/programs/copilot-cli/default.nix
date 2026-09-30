{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.programs.copilot-cli;

  configDir = "${config.home.homeDirectory}/.copilot";

  jsoncParser = pkgs.fetchzip {
    url = "https://registry.npmjs.org/jsonc-parser/-/jsonc-parser-3.3.1.tgz";
    hash = "sha256-eZb4Epz0UsTTaSstqBl46Sy/KRyKaJ+vBUJ92/6wsZY=";
  };

  # Deep-merges `patch` into the JSONC file at `path`, creating the file if it
  # doesn't exist yet. Keys the patch doesn't mention — auth tokens, state the
  # CLI writes on its own — and the user's comments pass through untouched.
  # Avoids `home.file`'s symlink-into-the-store approach: that would make the
  # file read-only, which breaks the CLI's own writes to it.
  jsonMergeScript = pkgs.writeShellScript "copilot-cli-json-merge" ''
    exec ${pkgs.nodejs}/bin/node ${pkgs.replaceVars ./merge-jsonc.js { inherit jsoncParser; }} "$@"
  '';

  jsonMerge = { path, patch }:
    "run ${jsonMergeScript} ${lib.escapeShellArg path} ${pkgs.writeText "copilot-cli-patch.json" (builtins.toJSON patch)}";

  # Grants a project (identified by its absolute path in permissions-config.json's
  # `locations`) extra trusted directories and/or pre-approved command patterns,
  # without disturbing anything else already recorded for that project or any
  # other. Directories are unioned/deduped; command patterns are merged into
  # one `{kind: "commands"}` tool_approvals entry (also unioned/deduped),
  # collapsing any existing commands entries into it without losing their
  # identifiers.
  #
  # Args: <perm-file> <project-path> <dir>... -- <command-pattern>...
  # (the "--" separator is required even when one side is empty)
  trustProjectScript = pkgs.writeShellScript "copilot-cli-trust-project" ''
    set -euo pipefail
    perm_file="$1"; proj="$2"; shift 2

    dirs=()
    cmds=()
    side=dirs
    for a in "$@"; do
      if [ "$a" = "--" ]; then side=cmds; continue; fi
      if [ "$side" = dirs ]; then dirs+=("$a"); else cmds+=("$a"); fi
    done

    mkdir -p "$(dirname "$perm_file")"
    [ -s "$perm_file" ] || echo '{}' > "$perm_file"

    dirs_json="$(printf '%s\n' "''${dirs[@]:-}" | sed '/^$/d' | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)"
    cmds_json="$(printf '%s\n' "''${cmds[@]:-}" | sed '/^$/d' | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)"

    tmp="$(mktemp "$perm_file.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    if ! ${pkgs.jq}/bin/jq --arg proj "$proj" --argjson dirs "$dirs_json" --argjson cmds "$cmds_json" '
      (.locations[$proj].allowed_directories // []) as $existingDirs
      | .locations[$proj].allowed_directories = (($existingDirs + $dirs) | unique)
      | (.locations[$proj].tool_approvals // []) as $approvals
      | ($approvals | map(select(.kind == "commands") | .commandIdentifiers // []) | add // []) as $existingCmds
      | (($existingCmds + $cmds) | unique) as $mergedCmds
      | if ($cmds | length) > 0 then
          .locations[$proj].tool_approvals =
            ([{kind: "commands", commandIdentifiers: $mergedCmds}]
             + ($approvals | map(select(.kind != "commands"))))
        else . end
    ' "$perm_file" > "$tmp"; then
      echo "copilot-cli: not updating $perm_file: it is not valid JSON" >&2
      exit 0
    fi
    mv "$tmp" "$perm_file"
  '';
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
            "run ${trustProjectScript} ${lib.escapeShellArg "${configDir}/permissions-config.json"} ${lib.escapeShellArg proj} "
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
          let
            script = pkgs.writeShellScript "copilot-cli-trust-parents" ''
              set -euo pipefail
              perm_file="$1"; parents_file="$2"; discover_root="$3"; shift 3

              parents=()

              if [ -f "$parents_file" ]; then
                while IFS= read -r parent || [ -n "$parent" ]; do
                  [ -z "$parent" ] && continue
                  parent="''${parent/#\~/$HOME}"
                  parents+=("''${parent%/}")
                done < "$parents_file"
              fi

              if [ -n "$discover_root" ] && [ -d "$discover_root" ]; then
                for group in "$discover_root"/*/; do
                  [ -d "$group" ] || continue
                  [ -e "$group.git" ] && continue
                  for child in "$group"*/; do
                    if [ -e "$child.git" ]; then
                      parents+=("''${group%/}")
                      break
                    fi
                  done
                done
              fi

              [ "''${#parents[@]}" -gt 0 ] || exit 0

              if [ -f "$perm_file" ] && ! ${pkgs.jq}/bin/jq empty "$perm_file" 2>/dev/null; then
                echo "copilot-cli: not updating $perm_file: it is not valid JSON" >&2
                exit 0
              fi

              printf '%s\n' "''${parents[@]}" | sort -u | while IFS= read -r parent; do
                [ -d "$parent" ] || continue
                for proj in "$parent"/*/; do
                  [ -e "$proj.git" ] || continue
                  ${trustProjectScript} "$perm_file" "''${proj%/}" "$@"
                done
              done
            '';
          in
          "run ${script} ${lib.escapeShellArg "${configDir}/permissions-config.json"} ${lib.escapeShellArg cfg.autoTrustSubdirsOf.file} ${lib.escapeShellArg (toString cfg.autoTrustSubdirsOf.discoverUnder)} "
          + lib.escapeShellArgs (cfg.autoTrustSubdirsOf.directories ++ [ "--" ] ++ cfg.autoTrustSubdirsOf.commandPatterns)
        )
      )
    );
  };
}
