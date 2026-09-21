# Declarative Beat Saber mod install. The mod payload itself (BSIPA + every
# mod in pkgs/beatsaber-mods/wanted-mods.json, deps resolved) is built by
# pkgs/beatsaber-mods — see that package for how to add a mod.
#
# Placement is two steps:
#   1. Copy activation (below) — the payload's top-level entries
#      (Plugins/, Libs/, IPA/, ...) mirror the game's own install-dir layout
#      1:1, so installing is merge-copying each into the live Steam install
#      (not symlinking — see the longer comment further down for why).
#      Runs on every home-manager switch.
#   2. `beatsaber-patch-mods` (below) — BSIPA's zip does NOT ship a
#      pre-built winhttp.dll; it ships IPA.exe, which has to be run ONCE
#      inside the game dir to binary-patch it and create winhttp.dll. Once
#      that file exists, BSIPA repatches itself automatically on every game
#      update, so this only needs a rerun if winhttp.dll goes missing (e.g.
#      a Steam "verify integrity"). Deliberately NOT wired into activation:
#      it has to run IPA.exe *inside the Wine/Proton prefix* (via
#      protontricks), which is a slow, external, Proton-version-dependent
#      process — same reasoning modules/emulation/content.nix gives for
#      keeping its rclone sync off activation and on a login/timer unit
#      instead. Run it by hand after the first switch, and again if you
#      ever see BSIPA "not installed" in-game.
#
# Deliberately NOT xdg.configFile, and deliberately NOT symlinks at all
# (tried both, in that order, against a real install):
#
# - A single top-level symlink per entry breaks BSIPA outright: it writes
#   new files under IPA/ at runtime (IPA/Backups/, IPA/Pending/), and a
#   directory that's ITSELF a symlink into the read-only nix store makes
#   those writes fail ("Access to the path ... is denied").
# - Making directories real+writable but symlinking the individual FILES
#   inside (a `cp -rs` farm) still breaks IPA.exe specifically: the .NET
#   CLR resolves a running executable's OWN location by following
#   symlinks, so IPA.exe (a symlink to /nix/store/...) computes its write
#   paths as "Z:\nix\store\...\IPA\Backups\..." — the store again — even
#   though it was invoked as "$gameDir/IPA.exe".
#
# So the payload is plain-copied (`cp -rf`) into the game install, then
# chmod u+w'd. This is the same thing BSIPA's own "extract the zip into
# the game folder" manual-install instructions do; the nix store just
# supplies the pinned, hashed source for the copy instead of a hand-
# downloaded zip. Costs real disk (a few MB of mod DLLs, not GBs) instead
# of dedup'd store space — worth it for a payload something executes.
# copy is a merge, not a sync: files the payload doesn't mention (a mod's
# own runtime state, e.g. UserData/, or user-downloaded custom songs) are
# never touched or pruned.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.beatsaber;

  # Bash snippet: populates a `gameDirs` array with every steamLibraryRoots
  # entry that both resolves to a directory AND already looks like a real
  # Beat Saber install. Shared between the activation's copy step and
  # beatsaber-patch-mods so both agree on "where is the game" without
  # duplicating the check (same pattern as modules/vr's steamvr-setcap unit)
  # -- and, critically, so neither one can independently forget it: Steam
  # can leave a "steamapps/common/Beat Saber" placeholder dir around from an
  # aborted/pending install of an app that isn't actually Beat Saber's, and
  # a plain glob/path match hits that just as happily as the real thing
  # (this bit us once: an empty placeholder under ~/.local/share/Steam got
  # populated with mod files while the real install sat under a second
  # library). Every consumer of $gameDirs can assume each entry is real.
  findGameDirs = ''
    shopt -s nullglob
    patterns=(
    ${lib.concatMapStringsSep "\n" (root:
      "  ${lib.escapeShellArg "${root}/steamapps/common/Beat Saber"}"
    ) cfg.steamLibraryRoots}
    )
    candidates=()
    old_ifs="$IFS"
    IFS=
    for pattern in "''${patterns[@]}"; do
      # shellcheck disable=SC2206 # unquoted on purpose: IFS is cleared above
      # so this performs pathname expansion without word-splitting the result.
      candidates+=( $pattern )
    done
    IFS="$old_ifs"

    gameDirs=()
    for candidate in "''${candidates[@]}"; do
      [ -d "$candidate" ] || continue
      if [ ! -e "$candidate/Beat Saber_Data" ] && [ ! -e "$candidate/Beat Saber.exe" ]; then
        echo "Warning: [beatsaber] $candidate doesn't look like a real Beat Saber install (no Beat Saber.exe/Beat Saber_Data) -- skipping" >&2
        continue
      fi
      gameDirs+=( "$candidate" )
    done
  '';

  patchModsScript = pkgs.writeShellApplication {
    name = "beatsaber-patch-mods";
    runtimeInputs = [ pkgs.protontricks ];
    text = ''
      ${findGameDirs}

      if [ "''${#gameDirs[@]}" -eq 0 ]; then
        echo "beatsaber-patch-mods: no Beat Saber install found under: ${lib.concatStringsSep ", " cfg.steamLibraryRoots}" >&2
        exit 1
      fi

      status=0
      for gameDir in "''${gameDirs[@]}"; do
        if [ -e "$gameDir/winhttp.dll" ] && [ "''${1:-}" != "--force" ]; then
          echo "beatsaber-patch-mods: $gameDir already patched (winhttp.dll present) — skipping. Pass --force to re-run."
          continue
        fi
        echo "beatsaber-patch-mods: running IPA.exe in $gameDir via protontricks (appid ${cfg.steamAppId})"
        # IPA.exe finds the game executable via its OWN working directory,
        # not an argument -- protontricks-launch doesn't cd into it first,
        # so it fails with "Could not locate game executable" if run from
        # anywhere else.
        if ! ( cd "$gameDir" && protontricks-launch --appid ${cfg.steamAppId} "$gameDir/IPA.exe" -n ); then
          echo "beatsaber-patch-mods: protontricks-launch failed for $gameDir" >&2
          status=1
        fi
      done
      exit "$status"
    '';
  };
in
{
  options.modules.beatsaber = {
    enable = lib.mkEnableOption "declarative Beat Saber mod install (BSIPA + wanted-mods.json)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.beatsaber-mods;
      description = "Built mod payload to install (see pkgs/beatsaber-mods).";
    };

    steamAppId = lib.mkOption {
      type = lib.types.str;
      default = "620980";
      description = "Beat Saber's Steam appid, used by beatsaber-patch-mods to find its Proton prefix.";
    };

    steamLibraryRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.home.homeDirectory}/.local/share/Steam" ];
      description = ''
        Glob roots to search for the Beat Saber install
        (`steamapps/common/Beat Saber`). Extend per host with any additional
        Steam library folder (e.g. a second drive) Steam is configured to
        install into. The first root where the game is actually found wins.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ patchModsScript ];

    home.activation.installBeatSaberMods = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${findGameDirs}

      if [ "''${#gameDirs[@]}" -eq 0 ]; then
        echo "Warning: [beatsaber] no Beat Saber install found under: ${lib.concatStringsSep ", " cfg.steamLibraryRoots}" >&2
      fi

      for gameDir in "''${gameDirs[@]}"; do
        for src in ${lib.escapeShellArg cfg.package}/*; do
          [ -e "$src" ] || continue
          name="$(basename "$src")"
          # Earlier switches (symlink-based, before this became a plain
          # copy) may have left "$gameDir/$name" as a bare symlink into an
          # old store path. Clear it first -- otherwise `cp` would follow
          # it and try to write through into the read-only store.
          if [ -L "$gameDir/$name" ]; then
            run rm "$gameDir/$name"
          fi
          if [ -d "$src" ]; then
            # Directory: merge-copy so files the payload doesn't mention
            # (mod runtime state, user data) are left alone; -f overwrites
            # only the files we DO ship, on every switch.
            run mkdir -p "$gameDir/$name"
            run cp -rf "$src"/. "$gameDir/$name/" \
              && run chmod -R u+w "$gameDir/$name" \
              || echo "Warning: [beatsaber] copy failed for $src -> $gameDir/$name" >&2
          else
            run cp -f "$src" "$gameDir/$name" \
              && run chmod u+w "$gameDir/$name" \
              || echo "Warning: [beatsaber] copy failed for $src -> $gameDir" >&2
          fi
        done
      done
    '';
  };
}
