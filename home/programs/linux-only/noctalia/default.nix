{ config, lib, pkgs, ... }:
let
  cfg = config.custom.noctalia;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.custom.noctalia.settings = lib.mkOption {
    type = tomlFormat.type;
    default = { };
    example = lib.literalExpression ''{ theme.mode = "dark"; }'';
    description = ''
      Declarative noctalia config, merged across modules and hosts and
      rendered to ~/.config/noctalia/config.toml.

      That file is a read-only store symlink, but nothing else is locked:
      Settings-menu changes land in ~/.local/state/noctalia/settings.toml and
      win over it, and any extra *.toml dropped next to config.toml loads
      alphabetically after it. Export the merged config from the Settings menu
      to copy a GUI tweak back here once it is worth sharing.
    '';
  };

  config.custom.noctalia.settings = lib.mapAttrsRecursive (_: lib.mkDefault) {
    location.auto_locate = true;
    # Grace only after an idle lock (needs the patched noctalia): swayidle's
    # idle timer passes `lock-session 30`, every other lock asks for the password.
    lockscreen = {
      grace_period_seconds = 30;
      grace_period_idle_only = true;
    };
    nightlight.enabled = true;
    theme = {
      source = "wallpaper";
      wallpaper_scheme = "m3-tonal-spot";
    };
    wallpaper.directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
  };

  config.programs.noctalia.settings = cfg.settings;
}
