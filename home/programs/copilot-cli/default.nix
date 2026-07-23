{ config, pkgs, lib, ... }:

{
  # GitHub Copilot CLI with token-savior MCP server integration
  # Token-savior provides structural code navigation tools that reduce token usage
  # by allowing the AI to navigate code by symbol rather than reading full files.
  #
  # Note: The bash compaction hooks (PreToolUse/PostToolUse) are not supported
  # in GitHub Copilot CLI yet, only the MCP server tools are available.

  # token-savior-stats and ts-stats are already provided by the claude-code
  # module (home/programs/claude-code) - they work across all clients since
  # they just read ~/.local/share/token-savior/*.json, so no need to
  # duplicate them here (would collision-error at build time).
  home.file.".config/copilot/mcp-config.json" = {
    enable = true;
    # command/env are a plain JSON string with no shell, so $PWD would be
    # taken literally rather than expanded. Wrap in bash -c (mirrors the
    # claude-code token-savior wrapper) so WORKSPACE_ROOTS picks up the
    # actual project dir Copilot CLI was launched from.
    text = builtins.toJSON {
      mcpServers = {
        token-savior = {
          command = "bash";
          args = [
            "-c"
            ''
              exec env WORKSPACE_ROOTS="$PWD" TOKEN_SAVIOR_CLIENT=copilot-cli TOKEN_SAVIOR_PROFILE=optimized \
                ${pkgs.token-savior}/bin/token-savior
            ''
          ];
        };
      };
    };
  };
}
