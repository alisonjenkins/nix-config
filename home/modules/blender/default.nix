{ config, lib, pkgs, ... }:
let
  cfg = config.modules.blender;
  # Blender stores per-user legacy add-ons under
  # ~/.config/blender/<major.minor>/scripts/addons. Deriving the version dir
  # from the installed package keeps the add-on in the default search path
  # (no need to override BLENDER_USER_SCRIPTS, which would hide other add-ons).
  blenderVersionDir = lib.versions.majorMinor cfg.package.version;
in
{
  options.modules.blender = {
    enable = lib.mkEnableOption "Blender with the BlenderMCP add-on for Claude-driven 3D modelling";

    package = lib.mkPackageOption pkgs "blender" { };

    enableMcpServer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register the blender-mcp server with Claude Code so Claude can drive
        Blender over the add-on's socket (localhost:9876). Requires
        programs.claude-code.enable (set repo-wide via home/programs).
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [ cfg.package ];

    # Install the BlenderMCP add-on declaratively. It still has to be enabled
    # once per Blender profile: Edit > Preferences > Add-ons > enable
    # "Interface: Blender MCP", then open View3D > Sidebar (N) > BlenderMCP and
    # click "Connect to MCP server" to start the socket the server talks to.
    home.file.".config/blender/${blenderVersionDir}/scripts/addons/blender_mcp_addon.py".source =
      "${pkgs.blender-mcp}/share/blender-mcp/addon.py";

    programs.claude-code.mcpServers = lib.mkIf cfg.enableMcpServer {
      blender = {
        command = lib.getExe pkgs.blender-mcp;
      };
    };
  };
}
