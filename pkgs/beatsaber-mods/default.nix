# Declarative Beat Saber mod payload: BSIPA + whatever's in wanted-mods.json,
# resolved (with dependencies) against the BeatMods API into
# beatsaber-mods.nix by generate-mods.py, and unzipped here into a tree that
# mirrors the game's own install directory layout (Plugins/, Libs/, IPA/,
# UserData/, ...). home/modules/beatsaber symlinks that tree's top-level
# entries into the live Steam install.
#
# To add a mod: browse https://beatmods.com/mods for the target
# gameVersion, add its name to wanted-mods.json, then re-run:
#   python3 generate-mods.py <game-version> wanted-mods.json beatsaber-mods.nix
# and commit the regenerated beatsaber-mods.nix.
{ stdenvNoCC, fetchurl, unzip, gameVersion ? "1.44.1" }:
let
  mods = import ./beatsaber-mods.nix { inherit fetchurl; };
in
stdenvNoCC.mkDerivation {
  pname = "beatsaber-mods";
  version = gameVersion;

  dontUnpack = true;
  nativeBuildInputs = [ unzip ];

  # Each mod zip's internal paths ARE the game-relative install paths (e.g.
  # BSIPA ships IPA/ and winhttp.dll at its zip root) — unzip -o merges them
  # into one tree, later mods in the (name-sorted) list overwriting earlier
  # ones on any file collision.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    ${builtins.concatStringsSep "\n" (map (m: ''
      echo "installing ${m.name} ${m.version}"
      unzip -o -q ${m.zip} -d $out
    '') mods)}
    runHook postInstall
  '';

  passthru.mods = mods;

  meta.description = "Declarative Beat Saber mod payload (BSIPA + wanted-mods.json), resolved via BeatMods API";
}
