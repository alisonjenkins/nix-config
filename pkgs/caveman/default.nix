{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "caveman";
  version = "0-unstable-2025-04-21";

  src = fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "84cc3c14fa1e10182adaced856e003406ccd250d";
    hash = "sha256-M+NoWXxrhtbkbe/lmq7P0/KpmqOZzJjhgeUVjY+7N2k=";
  };

  installPhase = ''
    mkdir -p $out
    cp -r hooks $out/hooks
    cp -r skills $out/skills
    chmod +x $out/hooks/caveman-statusline.sh
  '';

  meta = {
    description = "Claude Code skill cutting ~75% output tokens via caveman-speak";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
