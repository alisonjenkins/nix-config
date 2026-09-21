# Declarative Beat Saber mod install. The mod payload itself (BSIPA + every
# mod in pkgs/beatsaber-mods/wanted-mods.json, deps resolved) is built by
# pkgs/beatsaber-mods — see that package for how to add a mod.
#
# What's left here is placement: the payload's top-level entries (Plugins/,
# Libs/, IPA/, winhttp.dll, ...) mirror the game's own install-dir layout
# 1:1 (that's how BSIPA's "manual zip" install works — no exe patch step,
# winhttp.dll alone is what gets the game to load it), so installing is just
# symlinking each of those top-level entries into the live Steam install.
#
# Deliberately NOT xdg.configFile / a store symlink for the whole dir: the
# game (and other mods, e.g. downloaded custom songs under UserData/) needs
# to keep writing into that same tree, which a read-only store symlink would
# break. Same reasoning as modules/emulation/content.nix's
# symlinkActivationFor and home/modules/vr's seedVrRuntime.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.beatsaber;
in
{
  options.modules.beatsaber = {
    enable = lib.mkEnableOption "declarative Beat Saber mod install (BSIPA + wanted-mods.json)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.beatsaber-mods;
      description = "Built mod payload to install (see pkgs/beatsaber-mods).";
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
    home.activation.installBeatSaberMods = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
