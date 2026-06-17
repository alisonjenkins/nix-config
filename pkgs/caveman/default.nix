{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "caveman";
  version = "1.9.0-unstable-2025-06-15";

  src = fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    rev = "25d22f864ad68cc447a4cb93aefde918aa4aec9f";
    hash = "sha256-FbmfhFaPs/SnSZdfNdErdIUHXt1FfBzErpPpLy8kdIc=";
  };

  installPhase = ''
    mkdir -p $out/hooks $out/skills $out/opencode-plugin $out/opencode-commands

    # Claude Code hooks + skills (existing functionality)
    cp -r src/hooks/* $out/hooks/
    cp -r skills/* $out/skills/
    chmod +x $out/hooks/caveman-statusline.sh

    # opencode plugin files
    cp src/plugins/opencode/plugin.js $out/opencode-plugin/plugin.js
    cp src/plugins/opencode/package.json $out/opencode-plugin/package.json
    cp src/hooks/caveman-config.js $out/opencode-plugin/caveman-config.cjs

    # opencode slash commands
    cp src/plugins/opencode/commands/*.md $out/opencode-commands/
  '';

  meta = {
    description = "Claude Code + opencode skill cutting ~75% output tokens via caveman-speak";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
