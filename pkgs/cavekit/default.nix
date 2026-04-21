{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "cavekit";
  version = "4-unstable-2025-04-21";

  src = fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "cavekit";
    rev = "028643f913996cfe1c59f261627d167d4ab5477f";
    hash = "sha256-GOyHS+iYfOo79gm7rpFgL0mTf07+FjUa8T93MsRBMCk=";
  };

  installPhase = ''
    mkdir -p $out/skills $out/commands
    cp -r skills/. $out/skills/
    cp -r commands/. $out/commands/
  '';

  meta = {
    description = "Compressed spec-driven development for Claude Code (v4 — one spec, three commands)";
    homepage = "https://github.com/JuliusBrussee/cavekit";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
