{ lib, stdenvNoCC, fetchFromGitHub }:
stdenvNoCC.mkDerivation {
  pname = "superpowers";
  version = "6.0.2";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    # v6.0.2 — security-audited 2026-06-17. Bump only after re-auditing the new tree.
    rev = "b62616fc12f6a007c6fd5118146821d748da0d33";
    hash = "sha256-D47uMC80wcIMNzW/rA7VUVGc4hzlmcZJMCrLyp2lbAY=";
  };

  dontConfigure = true;
  dontBuild = true;

  # Claude Code plugin layout: .claude-plugin/plugin.json + skills/ + hooks/.
  # --preserve=mode keeps the +x bit on hooks/session-start, run-hook.cmd, and
  # the per-skill scripts (brainstorming/scripts/*.sh, subagent-driven-development
  # scripts, find-polluter.sh) as checked out from git.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r --preserve=mode .claude-plugin skills hooks $out/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Superpowers Claude Code plugin (TDD, debugging, brainstorming, planning skills) — pinned to security-audited v6.0.2";
    homepage = "https://github.com/obra/superpowers";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
