# Declarative Beat Saber mod payload: BSIPA + whatever's in wanted-mods.json,
# resolved (with dependencies) against the BeatMods API into
# beatsaber-mods.nix by generate-mods.py, and unzipped here into a tree that
# mirrors the game's own install directory layout (Plugins/, Libs/, IPA/,
# UserData/, ...). home/modules/beatsaber symlinks that tree's top-level
# entries into the live Steam install.
#
# gameVersion is pinned to 1.40.8, not the current default Beat Saber
# release: most of the mod ecosystem (ScoreSaber, BeatLeader, Chroma,
# NoodleExtensions, Heck, PlaylistManager) lags the game by months and
# wasn't verified for anything newer at the time this was pinned. 1.40.8 is
# Steam's `legacy1.40.8_unity_v2021.3.16f1` beta branch — the nearest
# actually-downloadable legacy build to where BeatMods coverage is good.
# Bumping this requires re-running generate-mods.py against the new
# version and checking BeatMods still covers every wanted mod first.
#
# To add a mod: browse https://beatmods.com/mods for the target
# gameVersion, add its name to wanted-mods.json, then re-run:
#   python3 generate-mods.py <game-version> wanted-mods.json beatsaber-mods.nix
# and commit the regenerated beatsaber-mods.nix.
{ stdenvNoCC, fetchurl, unzip, gameVersion ? "1.40.8" }:
let
  mods = import ./beatsaber-mods.nix { inherit fetchurl; };
in
stdenvNoCC.mkDerivation {
  pname = "beatsaber-mods";
  version = gameVersion;

  dontUnpack = true;
  nativeBuildInputs = [ unzip ];

  # Each mod zip's internal paths ARE the game-relative install paths (e.g.
  # BSIPA ships IPA.exe + IPA/ at its zip root, run once via
  # beatsaber-patch-mods to create winhttp.dll) — unzip -o merges them into
  # one tree, later mods in the (name-sorted) list overwriting earlier ones
  # on any file collision.
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
