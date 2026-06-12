{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

# MCP server half of BlenderMCP (https://github.com/ahujasid/blender-mcp).
# The companion in-app add-on (addon.py) is exposed under
# $out/share/blender-mcp/ for the home-manager module to install into Blender;
# the server connects to that add-on's socket (localhost:9876 by default).
python3Packages.buildPythonApplication rec {
  pname = "blender-mcp";
  version = "1.6.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ahujasid";
    repo = "blender-mcp";
    rev = "6e99eb5a442b83766a5796975ec7bb5bfc791341";
    hash = "sha256-X2kztoD64VBdZtUAVGRhD9+p9KZk8u1y2P6C+wxPz7A=";
  };

  build-system = [ python3Packages.setuptools ];

  # mcp[cli] at runtime only needs the base mcp library (fastmcp); the cli
  # extra (typer/python-dotenv) is for the `mcp` command, which is unused here.
  dependencies = with python3Packages; [
    mcp
    httpx
  ];

  # No test suite is shipped upstream.
  doCheck = false;
  pythonImportsCheck = [ "blender_mcp" ];

  # Ship the Blender add-on alongside the server so the home-manager module
  # can symlink it into Blender's add-ons directory.
  postInstall = ''
    install -Dm644 addon.py $out/share/blender-mcp/addon.py
  '';

  meta = {
    description = "MCP server connecting Blender to LLMs via the BlenderMCP add-on";
    homepage = "https://github.com/ahujasid/blender-mcp";
    license = lib.licenses.mit;
    mainProgram = "blender-mcp";
  };
}
