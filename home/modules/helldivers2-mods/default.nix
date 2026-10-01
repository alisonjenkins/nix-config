# Declarative scaffolding for Helldivers 2 modding via h2mm-cli
# (pkgs/h2mm-cli — see that package for why it's the pick: Nexus's own
# Arsenal mod manager has no Linux build yet, only Windows).
#
# What this module does NOT do: actually install a mod. Nexus gates
# scripted/API downloads behind a Premium account (see
# https://www.nexusmods.com/helldivers2/mods/16493 for DiverKit), so mod
# archives can't be nix-fetched by content hash the way pkgs/beatsaber-mods
# fetches from BeatMods. And h2mm's own `install`/`enable` commands rewrite
# the live game's data/ directory (numbered .patch_N archives, a mods.csv
# ledger) — running that unattended on every home-manager switch risks
# corrupting that state exactly the way modules/beatsaber's IPA.exe patch
# step is deliberately kept off activation (see that module's comment for
# the fuller reasoning). Both stay manual, imperative, run-by-hand steps:
#
#   1. Download a mod's zip from Nexus by hand into `cfg.modsDir`.
#   2. `h2mm install ~/mods/helldivers2/<mod>.zip` (then `h2mm enable`
#      if it doesn't prompt to).
#
# What IS safe to automate declaratively: finding the game's data/
# directory and pre-seeding h2mm's own path cache (~/.config/h2mm/h2path,
# a one-line plain-text file h2mm reads before falling back to an
# interactive `find`+prompt) so the first `h2mm` invocation doesn't stall
# waiting on a TTY prompt during a switch or from a non-interactive
# context. That file is just a path string outside the game install —
# safe to rewrite on every switch, same idempotence contract as any other
# activation step here.
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
    enable = lib.mkEnableOption "Helldivers 2 modding scaffolding (h2mm-cli + mods drop dir + h2path pre-seed)";

    steamLibraryRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.home.homeDirectory}/.local/share/Steam" ];
      description = ''
        Glob-free roots to search for the Helldivers 2 install
        (`steamapps/common/Helldivers 2`). Extend per host with any
        additional Steam library folder the game might live in instead.
        Only the first match is used — h2mm only tracks one game directory.
      '';
    };

    modsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/mods/helldivers2";
      description = ''
        Directory to manually drop downloaded mod zips into before running
        `h2mm install`. Created on activation; never synced or fetched into
        — Nexus mod archives have to be downloaded by hand (see the module
        header comment for why).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.h2mm-cli ];

    home.activation.seedH2mmPath = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${findGameDataDir}

      run mkdir -p ${lib.escapeShellArg cfg.modsDir}
      run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.config/h2mm"}

      if [ -n "$gameDataDir" ]; then
        run bash -c 'printf "%s" "$1" > "$2"' -- "$gameDataDir" ${lib.escapeShellArg "${config.home.homeDirectory}/.config/h2mm/h2path"}
      else
        echo "Warning: [helldivers2-mods] no Helldivers 2 install found under: ${lib.concatStringsSep ", " cfg.steamLibraryRoots} -- h2mm will prompt for its path on first run" >&2
      fi
    '';
  };
}
