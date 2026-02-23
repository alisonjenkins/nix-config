{ pkgs, ... }:
let
  anthropicSkills = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "skills";
    rev = "1ed29a03dc852d30fa6ef2ca53a67dc2c2c2c563";
    hash = "sha256-9FGubcwHcGBJcKl02aJ+YsTMiwDOdgU/FHALjARG51c=";
  };
in
{
  programs.claude-code = {
    enable = true;
    package =
      if pkgs.stdenv.isDarwin
      then pkgs.unstable.claude-code-bin
      else pkgs.unstable.claude-code;

    settings = {
      alwaysThinkingEnabled = true;
    };

    skillsDir = "${anthropicSkills}/skills";

    mcpServers = {
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
      };
    };
  };
}
