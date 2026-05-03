{ stdenvNoCC, lib, python3, makeWrapper }:
# Pre-flight tooling shared across Minecraft modpack server packages.
#
# `dep-tree` parses META-INF/neoforge.mods.toml from every jar in a
# server tree (recursing into JIJ children), builds provides/requires
# graphs, and surfaces unsatisfied or out-of-range required deps. Used:
#
#   1. From a modpack derivation's installPhase to fail builds before
#      docker image layering — see pkgs/create-arkana-aeronautics-server
#      for the integration pattern.
#   2. As an interactive tool (`nix run .#dep-tree -- /path/to/server`)
#      when iterating on a new modpack composition.
#
# The dep-tree script ships its own filename-pattern provider list
# tuned for Arkana + Create-family modpacks (kotlinforforge, flywheel,
# ponder JIJ, Aeronautics bundled simulated/offroad). Other modpacks
# can still use the script — the patterns are additive and don't
# interfere with unrelated jars.
stdenvNoCC.mkDerivation {
  pname = "minecraft-modpack-tools";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 dep-tree.py $out/bin/dep-tree
    # Ensure the shebang resolves to a Python with tomllib (3.11+).
    # makeWrapper isn't strictly needed here — the script's `import
    # tomllib` already gates on 3.11 — but the wrapper pins the Python
    # store path so PATH-environment changes can't subvert it.
    wrapProgram $out/bin/dep-tree --set PATH ${lib.makeBinPath [ python3 ]}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Pre-flight tooling for NeoForge / Forge modpack server compositions";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
