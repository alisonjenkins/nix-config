{ config, lib, pkgs, ... }:
let
  cfg = config.programs.rea;

  ghidra = import ./ghidra.nix pkgs;

  # One registration for both agents.
  server = {
    command = "${pkgs.rea}/bin/rea";
    args = [ "mcp" ];
    env = {
      GHIDRA_INSTALL_DIR = ghidra.installDir;
      JAVA_HOME = ghidra.javaHome;
    };
  };

  # mcp-gateway's backend `command` has no env, so the same environment goes
  # through a launcher.
  launcher = pkgs.writeShellScript "rea-mcp-launcher" ''
    export GHIDRA_INSTALL_DIR=${lib.escapeShellArg ghidra.installDir}
    export JAVA_HOME=${lib.escapeShellArg ghidra.javaHome}
    exec ${pkgs.rea}/bin/rea mcp
  '';

  # The shipped skill, plus where its tools live in Claude Code. Appended, so the
  # upstream frontmatter and references stay untouched.
  skills = pkgs.runCommand "rea-skills" { } ''
    cp -rL --no-preserve=mode ${pkgs.rea}/share/rea/skills $out
    cat >> $out/reverse-engineer-anything/SKILL.md <<'EOF'

    ## Loading REA here

    In Claude Code on this setup REA is not in the session's tool list. It runs behind
    the mcp-gateway, so its tool names cost no context in sessions that do not need it.
    Before any reverse-engineering work, load it through the gateway:

    1. `gateway_search_tools` with a keyword (for example `decompile`, `binary`, `apk`)
       finds REA's tools.
    2. `gateway_list_tools` with `server: "rea"` gives their input schemas.
    3. `gateway_invoke` with `server: "rea"`, the tool name and its arguments calls one.
       It asks for approval each time.

    Do not load REA for ordinary source-repository analysis. Copilot CLI registers REA
    directly, so there its tools appear without the gateway. Where neither applies (for
    example opencode), REA is not available.
    EOF
  '';
in
{
  options.programs.rea = {
    enable =
      lib.mkEnableOption "REA, the reverse-engineering MCP server and skill, for Claude Code and Copilot CLI";

    mcpLauncher = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      internal = true;
      default = launcher;
      description = "Executable that starts the REA MCP server, for hosts that cannot set env (the mcp-gateway).";
    };

    skills = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      internal = true;
      default = skills;
      description = "Directory of REA's skills, with the gateway loading note added.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Claude Code reaches REA through its mcp-gateway (claude-code/default.nix).
    programs.copilot-cli.mcpServers.rea = server;

    # Claude Code builds its own skill farm (claude-code/default.nix) and keys
    # off this option; ~/.agents/skills is what Copilot CLI and opencode read.
    home.file.".agents/skills/reverse-engineer-anything".source =
      "${cfg.skills}/reverse-engineer-anything";
  };
}
