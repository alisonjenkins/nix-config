{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "savvy-progress";
  version = "1.2.0-unstable-2026-10-04";

  src = fetchFromGitHub {
    owner = "JohnnyVizz";
    repo = "claude-kit";
    rev = "272a877f39b6971690e087b16a7cc3951b811e39";
    hash = "sha256-K+1MP18bP1NLkqQWu49IyKTbycng63sLdeLnMqDka/o=";
  };

  sourceRoot = "source/plugins/savvy-progress";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r .claude-plugin hooks types $out/
    runHook postInstall
  '';

  meta = {
    description = "Claude Code mod: progress bar above the prompt and a subagents panel (/agents-info)";
    homepage = "https://github.com/JohnnyVizz/claude-kit/tree/main/plugins/savvy-progress";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
