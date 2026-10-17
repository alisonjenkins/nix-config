{ config, lib, pkgs, ... }:
let
  cfg = config.modules.antigravityCli;
  mandates = import ../../programs/shared-mandates.nix;

  # Where programs/agent-skills links every shared skill.
  skillsDir = "${config.home.homeDirectory}/.agents/skills";
  settingsFile = "${config.home.homeDirectory}/.gemini/antigravity-cli/settings.json";

  # Skills are symlinks into the Nix store, and agy reads outside its
  # workspace only with a rule: headless runs deny the read, and an
  # interactive session would ask on every skill.
  allowRules = [
    "read_file(${skillsDir})"
    "read_file(/nix/store)"
  ];
in
{
  options.modules.antigravityCli = {
    enable = lib.mkEnableOption "your shared skills and mandates for Google's Antigravity CLI (agy)";
  };

  config = lib.mkIf cfg.enable {
    # agy does not scan ~/.agents/skills; a global skills.json declares it. The
    # path must be absolute: a ~/ path is silently ignored (agy 1.2.9, 1.2.16).
    home.file.".gemini/config/skills.json".text = builtins.toJSON {
      entries = [ { path = skillsDir; } ];
    };

    # Always-active global rules. Claude's Model Routing is left out, as it names
    # Claude's own cheaper models; agy gets its own, in model-routing.md.
    home.file.".gemini/config/AGENTS.md".text =
      mandates.gitStrategy + "\n" + mandates.workStyle + "\n" + builtins.readFile ./model-routing.md;

    # The subagent that routing sends work to, pinned to the Flash tier. Every
    # entry under `tools` must be a registered tool: an unknown name (command_status
    # was one) stops the agent from starting.
    home.file.".gemini/config/agents/flash-worker.md".source = ./flash-worker.md;

    # Routing text alone is advice: with it loaded, the main agent still did a
    # multi-file edit itself. This main agent has no edit or command tools, so it
    # has to hand those to flash-worker. Opt in with `agy --agent orchestrator`
    # or the /agents panel.
    home.file.".gemini/config/agents/orchestrator.md".source = ./orchestrator.md;

    # agy rewrites settings.json itself (trusted workspaces, colour scheme), so
    # the rules are merged in rather than the file being replaced.
    home.activation.antigravityCliPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings=${lib.escapeShellArg settingsFile}
      run mkdir -p "$(dirname "$settings")"
      if [ -s "$settings" ]; then
        base="$settings"
      else
        base="$(mktemp)"
        echo '{}' > "$base"
      fi
      merged="$(mktemp)"
      if ${pkgs.jq}/bin/jq --argjson add ${lib.escapeShellArg (builtins.toJSON allowRules)} \
          '.permissions.allow = ((.permissions.allow // []) + $add | unique)' \
          "$base" > "$merged"; then
        run mv "$merged" "$settings"
      else
        echo "warning: $settings is not valid JSON; skills stay unreadable by agy until it is fixed" >&2
        rm -f "$merged"
      fi
      [ "$base" = "$settings" ] || rm -f "$base"
    '';
  };
}
