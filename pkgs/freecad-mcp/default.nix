{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

# MCP server half of FreeCAD MCP (https://github.com/neka-nat/freecad-mcp).
# The companion FreeCAD workbench (addon/FreeCADMCP) is exposed under
# $out/share/freecad-mcp/ for the home-manager module to install into FreeCAD's
# Mod directory; the server connects to that workbench's RPC server (started
# from FreeCAD via the "Start RPC Server" command, localhost by default).
python3Packages.buildPythonApplication rec {
  pname = "freecad-mcp";
  version = "0.1.18";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    rev = "63acb305573194a011641ab13ccfb391fe95769f";
    hash = "sha256-MoYnDC9O4FkBjYLYR1FL9Z7R3q3/BdgMHUum47MMWfE=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    mcp
    validators
  ];

  # No test suite is shipped upstream.
  doCheck = false;
  pythonImportsCheck = [ "freecad_mcp" ];

  # Ship the FreeCAD workbench alongside the server so the home-manager module
  # can symlink it into FreeCAD's Mod directory.
  postInstall = ''
    mkdir -p $out/share/freecad-mcp/addon
    cp -r addon/FreeCADMCP $out/share/freecad-mcp/addon/
  '';

  meta = {
    description = "MCP server connecting FreeCAD to LLMs via the FreeCADMCP workbench";
    homepage = "https://github.com/neka-nat/freecad-mcp";
    license = lib.licenses.mit;
    mainProgram = "freecad-mcp";
  };
}
