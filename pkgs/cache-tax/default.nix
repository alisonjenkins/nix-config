{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "cache-tax";
  version = "2.2.1-unstable-2026-10-04";

  src = fetchFromGitHub {
    owner = "karanb192";
    repo = "cache-tax";
    rev = "06cac47ec125a41a4aeeb78a6b006bec8cc6d6ed";
    hash = "sha256-SPMPlWXvhBFBAmMsMI3RIQWWbw+XhGCnAxc1I0KPCOk=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r .claude-plugin hooks $out/
    runHook postInstall
  '';

  meta = {
    description = "Claude Code mod that keeps the prompt cache warm and prices a cold send";
    homepage = "https://github.com/karanb192/cache-tax";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
