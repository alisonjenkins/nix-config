# Declarative scaffolding for Helldivers 2 modding via Arsenal
# (pkgs/arsenal). Previously used h2mm-cli (pkgs/h2mm-cli) — switched after
# upstream deprecated h2mm-cli in favor of Arsenal (2025-09-30) and a
# confirmed, unfixed h2mm-cli bug surfaced: `h2mm list` shows a mod
# ENABLED, files land correctly in data/, but the mod has zero effect
# in-game (upstream issue #96). See the helldivers2-modding skill for the
# full incident writeup (same symptom reproduced here, root-caused via
# that issue, fixed by migrating to Arsenal).
#
# Also installs pkgs/hd2-repatcher, for when a game update desyncs a
# mod's unit resource IDs and it silently stops applying — run by hand
# the same way mod install/enable are, for the same live-state-mutation
# reason below.
#
# What this module does NOT do: actually install a mod. Nexus gates
# scripted/API downloads behind a Premium account (see
# https://www.nexusmods.com/helldivers2/mods/16493 for DiverKit), so mod
# archives can't be nix-fetched by content hash the way pkgs/beatsaber-mods
# fetches from BeatMods. And Arsenal's install/enable actions rewrite the
# live game's data/ directory (numbered .patch_N archives, a mods.csv
# ledger) — running that unattended on every home-manager switch risks
# corrupting that state exactly the way modules/beatsaber's IPA.exe patch
# step is deliberately kept off activation (see that module's comment for
# the fuller reasoning). Both stay manual, imperative, run-by-hand steps:
#
#   1. Download a mod's zip from Nexus by hand into `cfg.modsDir`.
#   2. Add/deploy it through Arsenal's own UI.
#
# What IS safe to automate declaratively: pre-seeding Arsenal's game-path
# setting. Unlike h2mm-cli's plain-text `~/.config/h2mm/h2path`, Arsenal
# keeps this (as `userGameDir`, the game's ROOT dir, not `data/`) inside
# `~/.config/hd2arsenal/hd2a_data.json` alongside a lot of other live
# state (mod list, deploy flags, UI prefs) — so activation `jq`-merges
# just that one key into the existing file instead of overwriting it
# wholesale, same idempotence contract as any other activation step here.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.helldivers2Mods;

  # Bash snippet: sets $gameDataDir to the first steamLibraryRoots entry
  # that resolves to a real Helldivers 2 install's data/ directory, or
  # leaves it empty. Checks for bin/helldivers2.exe alongside data/ so an
  # empty Steam-created placeholder dir (the beatsaber module hit exactly
  # this once) doesn't get treated as a real install.
  #
  # Not shared with home/modules/beatsaber's findGameDirs, modules/vr's
  # steamvr-setcap, or home/modules/subnautica-vr's game_dir lookup: same
  # "scan steamLibraryRoots for steamapps/common/<Game>" idea, but different
  # validation shape (first match requiring ALL markers here vs.
  # beatsaber/vr's multi-candidate array requiring ANY marker (or no
  # marker, for vr), vs. subnautica-vr's single fixed path with no marker
  # check). Unlike beatsaber/vr, this doesn't need glob expansion -- each
  # candidate is one exact literal path per root, not a pattern -- so
  # there's nothing to pull from lib/steam-glob-candidates.nix here. A
  # future fix to the steam-library-search approach (e.g. Flatpak Steam
  # paths) still needs to touch all four validation call sites.
  findGameDataDir = ''
    gameDataDir=""
    for root in ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.steamLibraryRoots}; do
      candidate="$root/steamapps/common/Helldivers 2"
      [ -d "$candidate/data" ] || continue
      [ -e "$candidate/bin/helldivers2.exe" ] || continue
      gameDataDir="$candidate/data"
      break
    done
  '';
in
{
  options.modules.helldivers2Mods = {
    enable = lib.mkEnableOption "Helldivers 2 modding scaffolding (Arsenal + hd2-repatcher + mods drop dir)";

    steamLibraryRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.home.homeDirectory}/.local/share/Steam" ];
      description = ''
        Glob-free roots to search for the Helldivers 2 install
        (`steamapps/common/Helldivers 2`). Extend per host with any
        additional Steam library folder the game might live in instead.
        Only the first match is used — fed into Arsenal's `userGameDir`
        setting on every activation.
      '';
    };

    modsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/mods/helldivers2";
      description = ''
        Directory to manually drop downloaded mod zips into before adding
        them through Arsenal. Created on activation; never synced or
        fetched into — Nexus mod archives have to be downloaded by hand
        (see the module header comment for why).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.arsenal pkgs.hd2-repatcher ];

    home.activation.seedArsenalGamePath = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${findGameDataDir}

      run mkdir -p ${lib.escapeShellArg cfg.modsDir}

      if [ -n "$gameDataDir" ]; then
        # Arsenal wants the game's ROOT dir (userGameDir), not data/ --
        # the opposite of h2mm-cli/hd2-repatcher, which both want data/.
        gameRootDir="''${gameDataDir%/data}"
        arsenalDataFile=${lib.escapeShellArg "${config.home.homeDirectory}/.config/hd2arsenal/hd2a_data.json"}
        run mkdir -p "$(dirname "$arsenalDataFile")"
        if [ -s "$arsenalDataFile" ]; then
          run bash -c '
            set -e
            tmp=$(mktemp)
            ${lib.getExe pkgs.jq} --arg dir "$1" "(.userGameDir) = \$dir" "$2" > "$tmp"
            mv "$tmp" "$2"
          ' -- "$gameRootDir" "$arsenalDataFile"
        else
          run bash -c '${lib.getExe pkgs.jq} -n --arg dir "$1" "{userGameDir: \$dir}" > "$2"' -- "$gameRootDir" "$arsenalDataFile"
        fi
      else
        echo "Warning: [helldivers2-mods] no Helldivers 2 install found under: ${lib.concatStringsSep ", " cfg.steamLibraryRoots} -- Arsenal will prompt for its path on first run" >&2
      fi
    '';
  };
}
