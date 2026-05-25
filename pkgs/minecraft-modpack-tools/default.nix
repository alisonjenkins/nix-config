{ stdenvNoCC, lib, python3, makeWrapper, rustPlatform }:
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
# `find-mod-bumps` walks the dep graph leaf-first to find the latest
# CurseForge/Modrinth release/beta of each pack mod compatible with both
# its own declared deps and existing dependents' version ranges. Output
# is a bump table + ready-to-paste extras.nix / overlays.nix replacement
# entries. Used as `nix run .#find-mod-bumps -- /path/to/server-tree`.
# Reads arkana-mods.nix + arkana-mods-extras.nix + overlays.nix from the
# cwd by default (override with --mods-nix / --extras-nix / --overlays-nix
# for other modpacks).
#
# The Rust port (find-mod-bumps/) parallelises both the per-mod listing
# fetch (cfwidget + Modrinth API) and the per-mod jar pre-download, and
# wraps all HTTP in an exponential-backoff retry loop. The retired
# python script ran serially and would take ~10+ min for the Arkana
# pack; the Rust binary completes the same walk in seconds when the
# disk cache is warm.
let
  find-mod-bumps = rustPlatform.buildRustPackage {
    pname = "find-mod-bumps";
    version = "0.2.0";
    src = ./find-mod-bumps;
    cargoLock.lockFile = ./find-mod-bumps/Cargo.lock;
    # No tests need network at build time — pure-logic unit tests + a
    # zip-roundtrip integration test all run offline.
    doCheck = true;
  };
in
stdenvNoCC.mkDerivation {
  pname = "minecraft-modpack-tools";
  version = "0.2.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 find-mod-bumps ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 dep-tree.py $out/bin/dep-tree
    # `dep-tree` still requires python (3.11+ for tomllib); pin the
    # interpreter so PATH-environment changes can't subvert it.
    wrapProgram $out/bin/dep-tree --set PATH ${lib.makeBinPath [ python3 ]}
    # find-mod-bumps is a standalone Rust binary — just expose it.
    ln -s ${find-mod-bumps}/bin/find-mod-bumps $out/bin/find-mod-bumps
    runHook postInstall
  '';

  meta = with lib; {
    description = "Pre-flight tooling for NeoForge / Forge modpack server compositions";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
