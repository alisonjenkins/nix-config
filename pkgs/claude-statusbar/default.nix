{ lib, fetchFromGitHub, python3Packages, claude-monitor }:

# claude-statusbar (leeguooooo/claude-code-usage-bar): a rich Claude Code status
# line — 5h/7d rate-limit usage, reset timers, projection, model + context window,
# prompt-cache countdown, project/branch/session lines. Ships the `cs`/`cstatus`/
# `claude-statusbar` CLI.
#
# Upstream has NO runtime deps (pyproject `dependencies = []`); the optional
# `claude-monitor` gives accurate official usage numbers — `core.py` locates it via
# `shutil.which('claude-monitor')`, so we put it on the CLI's PATH below. Without it
# the bar still renders in a less-accurate fallback mode.
#
# We deliberately use the inline render path (`cs`), not the `cs render` daemon: the
# daemon does launchd/systemd respawn + silent auto-upgrade (uv/pipx) work that has no
# place under Nix. The Claude Code integration (statusLine, slash commands, skill) is
# wired declaratively in home/programs/claude-code, so `cs --setup` is never run.
python3Packages.buildPythonApplication {
  pname = "claude-statusbar";
  version = "3.29.12";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "leeguooooo";
    repo = "claude-code-usage-bar";
    rev = "baa108c2ebd9320ae33bb6fd927b64d1ad006b17"; # v3.29.12
    hash = "sha256-TGgg7j2C+f90mGe7mVhz1NTpMDFX328vNrb4lM6Risc=";
  };

  build-system = [ python3Packages.setuptools python3Packages.wheel ];

  # Give `cs` an absolute claude-monitor on PATH so its accurate-usage path fires
  # regardless of the ambient PATH the statusLine subprocess inherits.
  makeWrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ claude-monitor ]) ];

  pythonImportsCheck = [ "claude_statusbar" ];

  # Surface the bundled slash commands + skill at a stable path so the
  # home-manager claude-code module can reference them by store path (the
  # package-data copies otherwise live buried under site-packages). `skills/`
  # already has the dir-of-skills shape: skills/claude-statusbar/SKILL.md.
  postInstall = ''
    mkdir -p $out/share/claude-statusbar
    cp -r src/claude_statusbar/commands $out/share/claude-statusbar/commands
    cp -r src/claude_statusbar/skills   $out/share/claude-statusbar/skills
  '';

  meta = {
    description = "Lightweight Claude Code status-line monitor for token/rate-limit usage";
    homepage = "https://github.com/leeguooooo/claude-code-usage-bar";
    license = lib.licenses.mit;
    mainProgram = "cs";
    platforms = lib.platforms.unix;
  };
}
