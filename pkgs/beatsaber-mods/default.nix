# Declarative Beat Saber mod payload: BSIPA + whatever's in wanted-mods.json,
# resolved (with dependencies) against the BeatMods API into
# beatsaber-mods.nix by generate-mods.py, and unzipped here into a tree that
# mirrors the game's own install directory layout (Plugins/, Libs/, IPA/,
# UserData/, ...). home/modules/beatsaber merge-copies that tree's
# top-level entries into the live Steam install (not symlinked — BSIPA
# writes new files inside the tree at runtime, and the .NET CLR resolves a
# running exe's own location through symlinks, both of which break against
# a symlink-based install).
#
# gameVersion is pinned (currently 1.40.8, not the current default Beat
# Saber release): most of the mod ecosystem (ScoreSaber, BeatLeader, Chroma,
# NoodleExtensions, Heck, PlaylistManager) lags the game by months and
# wasn't verified for anything newer at the time this was pinned. 1.40.8 is
# Steam's `legacy1.40.8_unity_v2021.3.16f1` beta branch — the nearest
# actually-downloadable legacy build to where BeatMods coverage is good.
#
# The pin lives ONLY in beatsaber-mods.nix's `gameVersion` field (set by
# generate-mods.py from the version it was actually run against) — not
# duplicated as an argument here, so there's no way for this derivation's
# reported version to drift from what the resolved mod set was actually
# built for. Bumping the version means re-running generate-mods.py against
# the new one (after checking BeatMods still covers every wanted mod) and
# committing the regenerated file; there's nothing to override here.
#
# To add a mod: browse https://beatmods.com/mods for the target
# gameVersion, add its name to wanted-mods.json, then re-run:
#   python3 generate-mods.py <game-version> wanted-mods.json beatsaber-mods.nix
# and commit the regenerated beatsaber-mods.nix.
{ stdenvNoCC, fetchurl, unzip }:
let
  generated = import ./beatsaber-mods.nix { inherit fetchurl; };
  inherit (generated) gameVersion mods;

  # BeatMods still serves BetterSongSearch 0.8.1 as "verified" for
  # gameVersion=1.40.8, but 0.8.1 only targets 1.39.1+/1.29.1 — its Harmony
  # patches silently no-op the in-game search UI on 1.40.8 (no exception,
  # the search tab just never appears). Upstream's fix is 0.8.2, built with
  # a dedicated DLL for the 1.39.1-1.40.8 range, which BeatMods hasn't
  # re-verified for 1.40.8 yet, so generate-mods.py can't see it. Drop this
  # override once a regenerate picks up 0.8.2 (or newer) on its own.
  betterSongSearchOverride = fetchurl {
    url = "https://github.com/kinsi55/BeatSaber_BetterSongSearch/releases/download/v0.8.2/BetterSongSearch.dll";
    name = "BetterSongSearch-0.8.2.dll";
    sha256 = "09ae4a8d1bca7bfa46c0002d889581f279541c1c913fbca83e8037b7a4e37685";
  };
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
    install -m444 ${betterSongSearchOverride} "$out/Plugins/BetterSongSearch.dll"
    runHook postInstall
  '';

  passthru.mods = mods;

  meta.description = "Declarative Beat Saber mod payload (BSIPA + wanted-mods.json), resolved via BeatMods API";
}
