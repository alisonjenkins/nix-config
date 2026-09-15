{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.audacityPatch;
  configFile = "${config.xdg.configHome}/audacity/audacity.cfg";

  setCmds = lib.concatLists (
    lib.mapAttrsToList (
      section: keys:
      lib.mapAttrsToList (
        key: value:
        "${lib.getExe pkgs.crudini} --set \"$target\" ${lib.escapeShellArg section} ${lib.escapeShellArg key} ${lib.escapeShellArg value}"
      ) keys
    ) cfg.settings
  );
in
{
  options.programs.audacityPatch = {
    enable = lib.mkEnableOption "patching specific keys in Audacity's own audacity.cfg";

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      example = {
        AudioIO = {
          Host = "ALSA";
        };
      };
      description = ''
        INI section -> key -> value overrides merged into
        ~/.config/audacity/audacity.cfg on every activation.

        Audacity owns this file -- it rewrites it constantly with window
        positions, recent-files lists and other runtime state that has
        nowhere else to live, so it can't be a plain home-manager symlink
        (a read-only store link would make Audacity fail to save its own
        state, the exact problem this module exists to avoid). Instead
        each declared key is patched in place with `crudini --set` on
        activation: only the listed section/key pairs are touched, and
        anything else already in the file -- including keys Audacity
        itself wrote -- is left alone. A key removed from this option
        stops being patched, but is not deleted from the file; unlike the
        Claude Code settings merge elsewhere in this repo, there is no
        single well-defined "nix-managed keys" set to diff against
        because the file is never nix-authored in the first place.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.audacityConfigPatch = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${configFile}"
      if [ ! -e "$target" ]; then
        run mkdir -p "$(dirname "$target")"
        run touch "$target"
      fi
      ${lib.concatStringsSep "\n      " setCmds}
    '';
  };
}
