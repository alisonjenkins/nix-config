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
  {
    # Redeclare vanilla tags some mods query during early
    # ResourceReload phases before vanilla's built-in tag data
    # propagates. The Sounds mod reads `#minecraft:cauldrons` from
    # its sheet_metal sound group and logs WARN if the tag resolves
    # empty — which fires LMFT's in-game "tags are cooked" chat
    # alert on every world load. Explicitly shipping the same values
    # as a datapack forces the tag loaded early and silences the
    # warning. Append-only (replace=false) so mods adding new
    # cauldron variants (Amendments adds dye_cauldron + liquid_
    # cauldron) keep their entries.
    filename = "ensure-vanilla-tags-1.0.zip";
    zip      = localDatapack "ensure-vanilla-tags";
  }
  {
    # Allow Create's contraption movement (pistons, bearings, rope
    # pulleys, super-glue assemblies, cart assemblers) to carry
    # minecraft:spawner blocks while preserving their tile-entity
    # state (stored entity type, spawn potentials, delay range).
    # Adds minecraft:spawner to create:safe_nbt via tag append
    # (replace=false). Default Create refuses to move blocks whose
    # tile-entity isn't in safe_nbt — this is the canonical knob.
    # Server-side change: contraption movement runs on the server.
    filename = "move-spawners-1.0.zip";
    zip      = localDatapack "move-spawners";
  }
]
