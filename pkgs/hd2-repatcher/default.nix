# hd2-repatcher (RaidingForPants/hd2-repatcher) — resyncs Helldivers 2 unit
# mod .patch files against the currently-installed game data after an
# Arrowhead update desyncs their unit resource IDs (see
# home/modules/helldivers2-mods and the helldivers2-modding skill for the
# full failure mode this fixes). Like h2mm itself, this stays a manual,
# run-by-hand tool — see pkgs/h2mm-cli's header for why mutating live game
# state can't be unattended activation.
#
# Upstream has no release tags (pyproject.toml's version trails the repo:
# 0.3.0 declared, latest tag is v0.2.5), so this is pinned by commit rev, not
# version. Bump both `rev` and `hash` together from
# https://github.com/RaidingForPants/hd2-repatcher when upstream moves.
#
# Only the CLI entry point is built: gui.py imports tkinter at module level,
# but cli.py only imports gui lazily when invoked with zero arguments — a
# path this package never takes (see home/modules/helldivers2-mods), so
# tkinter is deliberately left off the closure.
{
  lib,
  fetchFromGitHub,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "hd2-repatcher";
  version = "0-unstable-2026-09-30";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "RaidingForPants";
    repo = "hd2-repatcher";
    rev = "2222f6432ee3ead75a906b9a756618e4802a1ad5";
    hash = "sha256-jZt9XTVXdDOCa2vdX/P0uT/5Z/yxwi7XjvAPq4TSimU=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    lz4
    platformdirs
  ];

  # pyproject.toml pins exact versions of lz4/platformdirs, which fights
  # nixpkgs' own pinned versions of the same packages.
  pythonRelaxDeps = [ "platformdirs" "lz4" ];

  # The GUI entry point needs tkinter, which this package intentionally
  # excludes (see header comment) — only the CLI is usable here.
  postInstall = ''
    rm $out/bin/hd2-repatcher
  '';

  pythonImportsCheck = [
    "update_unit_mods"
    "slim"
    "settings"
  ];

  meta = {
    description = "Resyncs Helldivers 2 unit mod .patch files against the current game data after an update desyncs them";
    homepage = "https://github.com/RaidingForPants/hd2-repatcher";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hd2-repatcher-cli";
  };
}
