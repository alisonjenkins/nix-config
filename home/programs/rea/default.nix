{ config, lib, pkgs, ... }:
let
  cfg = config.programs.rea;

  # One registration for both agents. REA needs Ghidra 12.1.x and a full
  # JDK 21+; nixos-unstable's ghidra-bin satisfies `rea doctor --provider ghidra`.
  server = {
    command = "${pkgs.rea}/bin/rea";
    args = [ "mcp" ];
    env = {
      GHIDRA_INSTALL_DIR = "${pkgs.unstable.ghidra-bin}/lib/ghidra";
      JAVA_HOME = "${pkgs.unstable.jdk21}/lib/openjdk";
    };
  };
in
{
  options.programs.rea.enable =
    lib.mkEnableOption "REA, the reverse-engineering MCP server and skill, for Claude Code and Copilot CLI";

  config = lib.mkIf cfg.enable {
    programs.claude-code.mcpServers.rea = server;
    programs.copilot-cli.mcpServers.rea = server;

    # Claude Code builds its own skill farm (claude-code/default.nix) and keys
    # off this option; ~/.agents/skills is what Copilot CLI and opencode read.
    home.file.".agents/skills/reverse-engineer-anything".source =
      "${pkgs.rea}/share/rea/skills/reverse-engineer-anything";
  };
}
