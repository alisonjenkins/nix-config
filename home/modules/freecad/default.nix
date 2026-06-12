{ config, lib, pkgs, ... }:
let
  cfg = config.modules.freecad;
in
{
  options.modules.freecad = {
    enable = lib.mkEnableOption "FreeCAD with the FreeCADMCP workbench for Claude-driven parametric CAD";

    package = lib.mkPackageOption pkgs "freecad" { };

    modDir = lib.mkOption {
      type = lib.types.str;
      default = ".local/share/FreeCAD/Mod";
      example = ".local/share/FreeCAD/v1-1/Mod";
      description = ''
        Home-relative FreeCAD Mod directory the FreeCADMCP workbench is
        installed into. FreeCAD 1.0 uses .local/share/FreeCAD/Mod; FreeCAD 1.1
        uses .local/share/FreeCAD/v1-1/Mod. Adjust to match cfg.package.
      '';
    };

    enableMcpServer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register the freecad-mcp server with Claude Code so Claude can drive
        FreeCAD over the workbench's RPC server. Requires
        programs.claude-code.enable (set repo-wide via home/programs).
      '';
    };
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.isLinux) {
    home.packages = [ cfg.package ];

    # Install the FreeCADMCP workbench. FreeCAD auto-loads workbenches found in
    # Mod/; start the RPC server it adds via the "Start RPC Server" command
    # (FreeCAD MCP toolbar) so the server has something to connect to.
    home.file."${cfg.modDir}/FreeCADMCP".source =
      "${pkgs.freecad-mcp}/share/freecad-mcp/addon/FreeCADMCP";

    programs.claude-code.mcpServers = lib.mkIf cfg.enableMcpServer {
      freecad = {
        command = lib.getExe pkgs.freecad-mcp;
      };
    };
  };
}
