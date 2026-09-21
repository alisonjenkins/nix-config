{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.subnauticaVR;

  modPackage = pkgs.subnautica-vr-mods.override { inherit (cfg) mode; };

  syncScript = pkgs.writeShellApplication {
    name = "subnautica-vr-mod-sync";
    runtimeInputs = [
      pkgs.rsync
      pkgs.coreutils
    ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "subnautica-vr-mod-sync: usage: subnautica-vr-mod-sync <command> [args...]" >&2
        echo "subnautica-vr-mod-sync: set this as a Steam launch option, e.g. \"subnautica-vr-mod-sync %command%\"" >&2
        exit 1
      fi

      game_dir="${cfg.steamLibraryPath}/steamapps/common/Subnautica"

      if [ ! -d "$game_dir" ]; then
        echo "subnautica-vr-mod-sync: Subnautica not found at $game_dir, skipping mod sync" >&2
      else
        # Both mods' plugin DLLs, removed unconditionally before syncing:
        # rsync alone only ever adds or updates files, so without this a
        # mode switch would leave both plugins loaded at once instead of
        # the mutually-exclusive set upstream requires.
        rm -f "$game_dir/BepInEx/plugins/SubmersedVR.dll" "$game_dir/BepInEx/plugins/VREnhancements.dll"
        # --no-owner --no-group: the payload is owned by the nix build user,
        # not whoever launches Steam. `-a` (which includes -o/-g) tries to
        # chown to that uid/gid, fails as a non-root user, and rsync's
        # nonzero exit trips `set -e` — aborting the whole game launch.
        # --chmod: copying a read-only nix store tree with plain -a would
        # land every file read-only in $game_dir, and BepInEx writes its own
        # log and rewrites BepInEx/config/BepInEx.cfg on every launch —
        # both need to stay writable.
        #
        # No --checksum: -a's default quick check (size + mtime, and -a
        # preserves mtime via -t) already tells a changed nix store path
        # apart from an already-synced one, since the store is content-
        # addressed and immutable. --checksum would force a full read+hash
        # of every file on every launch for no gain.
        rsync -a --no-owner --no-group --chmod=Du=rwx,Fu=rw ${modPackage}/ "$game_dir"/
        echo "subnautica-vr-mod-sync: synced ${cfg.mode} mod payload into $game_dir" >&2
      fi

      # BepInEx.Subnautica's doorstop injects via a winhttp.dll placed in the
      # game dir; Wine only loads it in place of the system DLL when told to
      # via WINEDLLOVERRIDES, and only once, not always (winhttp is also a
      # normal Windows system DLL other overrides may already be listing).
      # Entries are `;`-separated; `,` is only for the dll/mode list within
      # one entry (winhttp=n,b itself), not between entries.
      export WINEDLLOVERRIDES="winhttp=n,b''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      exec "$@"
    '';
  };
in
{
  options.modules.subnauticaVR = {
    enable = lib.mkEnableOption "Subnautica VR mod sync (BepInEx + SubmersedVR/VR Enhancements)";

    mode = lib.mkOption {
      type = lib.types.enum [
        "submersed"
        "enhancements"
      ];
      default = "submersed";
      description = ''
        Which VR mod to layer on top of BepInEx. Upstream-documented as
        mutually exclusive, not stackable:

        - `submersed`: SubmersedVR — real motion-controller support, SteamVR
          only, explicitly WIP/unpolished upstream. Overwrites the game's own
          `SteamVR.dll`/`SteamVR_Actions.dll` and controller binding JSON.
        - `enhancements`: Subnautica VR Enhancements — comfort/QoL fixes
          (HUD, PDA placement, subtitles, cursor, walk speed) for the
          original gamepad/keyboard-driven native VR mode. More polished,
          no motion controllers.

        Switching from `submersed` to `enhancements` does not restore the
        overwritten SteamVR DLLs/bindings — the sync is an overlay, not a
        snapshot-and-restore. Use Steam's "Verify integrity of game files" on
        Subnautica to restore the originals after switching away from
        `submersed`.
      '';
    };

    steamLibraryPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/Steam";
      description = ''
        Steam library root containing `steamapps/common/Subnautica`. Override
        for a game installed on a secondary library folder.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ syncScript ];
  };
}
