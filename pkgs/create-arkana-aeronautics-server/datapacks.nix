# Datapacks bundled into both the server tree and the client zip.
# Server-side ships them at /opt/server/openloader/data/<zip>; client zip
# mirrors at overrides/openloader/data/<zip>. OpenLoader (overlay mod)
# auto-loads zips from <game-dir>/openloader/data/ into every world the
# server hosts and every world the client opens, so a single declarative
# list applies uniformly without per-world manual installation.
#
# Each list entry must have { filename = "..."; zip = <derivation>; }.
# Two helpers are provided:
#   - `fetchurl` for off-the-shelf upstream datapack downloads.
#   - `localDatapack` builds a zip from a source folder under ./datapacks/.
#     Drop your datapack source as ./datapacks/<name>/{pack.mcmeta,data/...}
#     and reference it as `localDatapack "<name>"`.
#
# Add new datapacks by appending entries to the list at the bottom.
{ fetchurl ? null, stdenvNoCC ? null, zip ? null }:

let
  localDatapack = name:
    assert stdenvNoCC != null;
    assert zip != null;
    stdenvNoCC.mkDerivation {
      name = "${name}-datapack";
      src = ./datapacks + "/${name}";
      nativeBuildInputs = [ zip ];
      buildPhase = ''
        runHook preBuild
        ${zip}/bin/zip -r9 datapack.zip . -x '.*' '*/.*'
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -m644 datapack.zip "$out"
        runHook postInstall
      '';
    };
in
[
  {
    # Ice and Fire pixies cluster around pixie villages and harass players
    # by stealing inventory items on contact. The mod's PixieConfig only
    # exposes `size` + `stealItems` (no spawn-rate knob), but the
    # underlying density is driven by how many pixie-village structures
    # generate. Default pixie_village structure_set has spacing=8
    # separation=4 (chunks) — extremely dense compared to e.g. vanilla
    # villages (spacing=32). Override to spacing=32 separation=12 → 4×
    # rarer villages → ~4× fewer pixies wandering, without removing the
    # mob entirely (spawn eggs + the remaining villages still produce
    # pixies for the pixie-dust craft).
    filename = "rare-pixie-villages-1.0.zip";
    zip      = localDatapack "rare-pixie-villages";
  }
]
