{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "pup-claude";
  version = "0.64.1";

  src = fetchFromGitHub {
    owner = "DataDog";
    repo = "pup";
    rev = "v0.64.1";
    hash = "sha256-GdcQ04giQWhHnt+OMnxrccDY+fjbudUEZKQ4svfsrk0=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/.claude-plugin $out/skills $out/agents
    cp .claude-plugin/plugin.json $out/.claude-plugin/plugin.json
    cp -r skills/.  $out/skills/
    cp -r agents/.  $out/agents/
    runHook postInstall
  '';

  meta = {
    description = "Claude Code plugin for Datadog pup CLI (dd-* skills + 49 domain agents)";
    homepage = "https://github.com/DataDog/pup";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
