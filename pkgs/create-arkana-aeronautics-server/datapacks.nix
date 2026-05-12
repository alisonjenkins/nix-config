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
    # Ice and Fire pixies spawn frequently in overworld biomes and lift
    # items out of player inventories. The mod's PixieConfig in 1.21.1
    # exposes only `size` + `stealItems` (no spawn-rate knob), so the
    # cleanest cull is a NeoForge biome modifier that removes pixie
    # spawns from every overworld biome. Spawn eggs + pixie-village
    # structures still produce pixies for the pixie-dust craft path.
    filename = "no-pixies-1.0.zip";
    zip      = localDatapack "no-pixies";
  }
]
