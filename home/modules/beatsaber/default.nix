# Declarative Beat Saber mod install. The mod payload itself (BSIPA + every
# mod in pkgs/beatsaber-mods/wanted-mods.json, deps resolved) is built by
# pkgs/beatsaber-mods — see that package for how to add a mod.
#
# Placement is two steps:
#   1. Symlink activation (below) — the payload's top-level entries
#      (Plugins/, Libs/, IPA/, ...) mirror the game's own install-dir layout
#      1:1, so installing is symlinking each into the live Steam install.
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
# Deliberately NOT xdg.configFile / a store symlink for the whole dir: the
# game (and other mods, e.g. downloaded custom songs under UserData/) needs
# to keep writing into that same tree, which a read-only store symlink would
# break. Same reasoning as modules/emulation/content.nix's
# symlinkActivationFor and home/modules/vr's seedVrRuntime.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.beatsaber;

  # Bash snippet: populates a `gameDirs` array with every steamLibraryRoots
  # glob pattern that currently resolves to a directory. Shared between the
  # activation symlinker and beatsaber-patch-mods so both agree on "where is
  # the game" without duplicating the glob-expansion dance (same pattern as
  # modules/vr's steamvr-setcap unit).
  findGameDirs = ''
    shopt -s nullglob
    patterns=(
    ${lib.concatMapStringsSep "\n" (root:
      "  ${lib.escapeShellArg "${root}/steamapps/common/Beat Saber"}"
    ) cfg.steamLibraryRoots}
    )
    gameDirs=()
    old_ifs="$IFS"
    IFS=
    for pattern in "''${patterns[@]}"; do
      gameDirs+=( $pattern )
    done
    IFS="$old_ifs"
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
        if ! protontricks-launch --appid ${cfg.steamAppId} "$gameDir/IPA.exe" -n; then
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
        [ -d "$gameDir" ] || continue
        run mkdir -p "$gameDir"
        for src in ${lib.escapeShellArg cfg.package}/*; do
          [ -e "$src" ] || continue
          run ln -sfn "$src" "$gameDir/$(basename "$src")" \
            || echo "Warning: [beatsaber] symlink failed for $src -> $gameDir" >&2
        done
      done
    '';
  };
}
