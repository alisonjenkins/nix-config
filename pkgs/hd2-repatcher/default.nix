# hd2-repatcher (RaidingForPants/hd2-repatcher) — resyncs Helldivers 2 unit
# mod .patch files against the currently-installed game data after an
# Arrowhead update desyncs their unit resource IDs (see
# home/modules/helldivers2-mods and the helldivers2-modding skill for the
# full failure mode this fixes). Like deploying a mod through Arsenal,
# this stays a manual, run-by-hand tool — mutating live game state can't
# be an unattended activation step (see home/modules/helldivers2-mods's
# header).
#
# Pinned by commit rev, not version: pyproject.toml declares 0.3.0, which
# is already ahead of the latest tag (v0.2.5) — the current code is
# untagged, not a version behind its tags. Bump both `rev` and `hash`
# together from https://github.com/RaidingForPants/hd2-repatcher when
# upstream moves.
#
# Only one binary is built: upstream's pyproject.toml defines both
# `hd2-repatcher` and `hd2-repatcher-cli` as the same `cli:main` console
# script, so they're identical except for name. `postInstall` below drops
# the duplicate `hd2-repatcher` name. (Separately, `gui.py` — reachable
# only via `cli.py`'s lazy `from gui import run_gui` when invoked with
# zero arguments, a path this package never takes — needs tkinter, which
# is deliberately left off this closure either way.)
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

  # hd2-repatcher and hd2-repatcher-cli are the same cli:main entry point
  # under two names (see header comment) — drop the duplicate.
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
